data "aws_partition" "current" {}

locals {
  cluster_name             = "${var.name_prefix}-expense-eks"
  eks_admin_access         = var.enabled && var.eks_admin_principal_arn != ""
  eks_ci_access            = var.enabled && var.eks_ci_principal_arn != "" && var.eks_ci_principal_arn != var.eks_admin_principal_arn
  cluster_admin_policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

# VPC/subnets/NAT/routing all live in the independent network layer now
# (terraform-network/) -- this module only consumes var.vpc_id/public_subnet_ids/
# private_subnet_ids, read from that layer's SSM parameters by the root config.
#
# The network layer itself doesn't (and shouldn't) know these subnets will be
# used by EKS specifically -- it's runtime-agnostic, shared with ECS too. So
# the EKS-specific discovery tags the AWS Load Balancer Controller and EKS
# itself rely on get *added* here, onto subnets this module doesn't own,
# via aws_ec2_tag -- the standard Terraform pattern for "another layer's
# resource needs one more tag from me" without taking ownership of the whole
# resource.
resource "aws_ec2_tag" "public_subnet_cluster" {
  for_each = var.enabled ? toset(var.public_subnet_ids) : toset([])

  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "public_subnet_elb_role" {
  for_each = var.enabled ? toset(var.public_subnet_ids) : toset([])

  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "private_subnet_cluster" {
  for_each = var.enabled ? toset(var.private_subnet_ids) : toset([])

  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "private_subnet_internal_elb_role" {
  for_each = var.enabled ? toset(var.private_subnet_ids) : toset([])

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

# Step 7: ALB security group — created by us in Terraform so we can reference it
# in the node SG rules and pass it to the Ingress via annotation.
# The LB Controller will use THIS SG for the ALB instead of creating one itself.
resource "aws_security_group" "eks_alb" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-eks-alb-"
  description = "ALB for EKS Ingress - internet-facing HTTP"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound to Pods (target-type: ip)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # LBC v2 IAM conditions key off elbv2.k8s.aws/cluster (not the v1 ingress.k8s.aws/cluster tag).
  tags = {
    Name                      = "${var.name_prefix}-eks-alb"
    "elbv2.k8s.aws/cluster"   = local.cluster_name
    "ingress.k8s.aws/cluster" = local.cluster_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow ALB -> backend Pod port (8080) and frontend Pod port (80) on nodes.
resource "aws_security_group_rule" "node_ingress_from_alb_backend" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "ALB to backend Pod (8080)"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node[0].id
  source_security_group_id = aws_security_group.eks_alb[0].id
}

resource "aws_security_group_rule" "node_ingress_from_alb_frontend" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "ALB to frontend Pod (80)"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node[0].id
  source_security_group_id = aws_security_group.eks_alb[0].id
}

# SSM publish for this moved out to environments/{env}/compute/main.tf --
# modules/ never talks to SSM (see modules/security for the same rule).

# Step 2: explicit security groups (learning baseline, close to real projects).
# - EKS still creates the "cluster primary" security group automatically; we attach an additional SG to the
#   control-plane cross-account ENIs and a dedicated node SG on workers (via launch template).
resource "aws_security_group" "eks_cluster_additional" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-eks-cp-"
  description = "Additional SG for EKS control plane ENIs in this VPC"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-eks-cluster-additional"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "eks_node" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-eks-node-"
  description = "EKS managed node group - worker instances"
  vpc_id      = var.vpc_id

  egress {
    description = "Outbound via NAT (images, AWS APIs, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-eks-node"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API server endpoint (private) — nodes must reach control plane ENIs on 443.
resource "aws_security_group_rule" "cluster_additional_ingress_from_nodes_https" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "Nodes to Kubernetes API (HTTPS)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster_additional[0].id
  source_security_group_id = aws_security_group.eks_node[0].id
}

# Pod / kube-proxy style traffic between nodes (same SG).
resource "aws_security_group_rule" "node_ingress_self_all" {
  count = var.enabled ? 1 : 0

  type              = "ingress"
  description       = "Node-to-node cluster traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_node[0].id
  self              = true
}

# eks_cluster and eks_node_group IAM roles used to be created here. They're
# now owned by the security layer (terraform-security/) -- their trust
# policies only name eks.amazonaws.com / ec2.amazonaws.com, no dependency on
# this cluster, so Security can pre-provision them and this module just
# consumes the ARNs (var.eks_cluster_role_arn / var.eks_node_role_arn).

resource "aws_eks_cluster" "expense" {
  count = var.enabled ? 1 : 0

  name     = local.cluster_name
  role_arn = var.eks_cluster_role_arn
  version  = var.eks_kubernetes_version

  access_config {
    authentication_mode = "API"
    # Grant cluster-admin to the IAM principal that runs CreateCluster (e.g. CI pilotuser on first apply).
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.eks_cluster_additional[0].id]
  }

  # AWS requires AmazonEKSClusterPolicy to already be attached to the role
  # before CreateCluster succeeds -- this used to be an in-state depends_on
  # on the attachment resource. Now that the role+attachment live in the
  # security layer (terraform-security/), that ordering can't be expressed
  # as a Terraform dependency across states: it's an *apply-order*
  # requirement instead -- security must be applied (and its SSM parameters
  # populated) before compute, on any environment being built fresh. This is
  # a real tradeoff of splitting IAM into its own layer, worth calling out.
}

# After the cluster exists: EKS cluster primary SG -> kubelet on nodes (required when using extra node SGs).
resource "aws_security_group_rule" "node_ingress_kubelet_from_cluster_primary" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "Kubelet from EKS cluster primary security group"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node[0].id
  source_security_group_id = aws_eks_cluster.expense[0].vpc_config[0].cluster_security_group_id
}

resource "aws_launch_template" "eks_node" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-eks-node-lt-"

  # AWS requires the cluster primary SG plus any custom node SGs on managed nodes.
  vpc_security_group_ids = [
    aws_eks_cluster.expense[0].vpc_config[0].cluster_security_group_id,
    aws_security_group.eks_node[0].id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.name_prefix}-eks-node-lt"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_eks_cluster.expense]
}

# Human/admin kubectl access (set var.eks_admin_principal_arn). IRSA handles app Pod AWS API calls separately.
resource "aws_eks_access_entry" "cluster_admin" {
  count = local.eks_admin_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  count = local.eks_admin_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_admin_principal_arn
  policy_arn    = local.cluster_admin_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_admin[0]]
}

# CI automation user (pilotuser) — separate from the human admin principal.
resource "aws_eks_access_entry" "cluster_ci" {
  count = local.eks_ci_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_ci_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_ci" {
  count = local.eks_ci_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_ci_principal_arn
  policy_arn    = local.cluster_admin_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_ci[0]]
}

resource "aws_eks_node_group" "expense_default" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.expense[0].name
  node_group_name = "${var.name_prefix}-expense-default"
  node_role_arn   = var.eks_node_role_arn
  # Pinned to AZ1 only — with desired_size=1 per group, letting the ASG pick from
  # all AZs (the old var.private_subnet_ids[*] unfiltered) means node groups can
  # land in the same AZ by chance (this happened in prod). Pinning one group per
  # AZ guarantees 1 node per zone at the same node count — no extra cost.
  subnet_ids     = [var.private_subnet_ids[0]]
  instance_types = var.eks_node_instance_types
  # Without this, bumping the cluster's Kubernetes version does NOT touch node
  # groups — confirmed empirically (plan showed 0 changes here after a control-plane
  # version bump). This is what actually triggers the node (kubelet/AMI) upgrade.
  version = var.eks_kubernetes_version

  launch_template {
    id      = aws_launch_template.eks_node[0].id
    version = aws_launch_template.eks_node[0].latest_version
  }

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  # Default is already max_unavailable=1; declared explicitly so the rollout
  # behavior is documented, not implied. With 1 node per group, this just means
  # "replace this one node" — the real safety net during that replacement is the
  # PodDisruptionBudgets in expenseapp's k8s/eks-workload.yaml, not this setting.
  update_config {
    max_unavailable = 1
  }

  # The three worker-node policy attachments (worker-node/CNI/ECR-pull) that
  # used to be listed here now live in the security layer, already attached
  # to var.eks_node_role_arn before this module ever runs (same apply-order
  # reasoning as the cluster role above) -- not expressible as depends_on
  # across states, so they're dropped from this list rather than left dangling.
  depends_on = [
    aws_security_group_rule.node_ingress_kubelet_from_cluster_primary,
    aws_launch_template.eks_node
  ]
}

# Step 3: second node group. Same IAM role and launch template as the first group —
# the distinction is the label (role=apps) so that in a later step we can steer
# workloads to specific node groups with nodeSelector or affinity rules.
resource "aws_eks_node_group" "expense_apps" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.expense[0].name
  node_group_name = "${var.name_prefix}-expense-apps"
  node_role_arn   = var.eks_node_role_arn
  # AZ2 — see expense_default above.
  subnet_ids     = [var.private_subnet_ids[1]]
  instance_types = var.eks_node_instance_types
  # See expense_default above — this is what actually triggers the node upgrade.
  version = var.eks_kubernetes_version

  launch_template {
    id      = aws_launch_template.eks_node[0].id
    version = aws_launch_template.eks_node[0].latest_version
  }

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "apps"
  }

  # The three worker-node policy attachments (worker-node/CNI/ECR-pull) that
  # used to be listed here now live in the security layer, already attached
  # to var.eks_node_role_arn before this module ever runs (same apply-order
  # reasoning as the cluster role above) -- not expressible as depends_on
  # across states, so they're dropped from this list rather than left dangling.
  depends_on = [
    aws_security_group_rule.node_ingress_kubelet_from_cluster_primary,
    aws_launch_template.eks_node
  ]
}

# Step 4: third node group, added when the network layer moved to 3 AZs —
# same one-group-per-AZ pinning as expense_default/expense_apps above.
resource "aws_eks_node_group" "expense_extra" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.expense[0].name
  node_group_name = "${var.name_prefix}-expense-extra"
  node_role_arn   = var.eks_node_role_arn
  # AZ3 — see expense_default above.
  subnet_ids     = [var.private_subnet_ids[2]]
  instance_types = var.eks_node_instance_types
  # See expense_default above — this is what actually triggers the node upgrade.
  version = var.eks_kubernetes_version

  launch_template {
    id      = aws_launch_template.eks_node[0].id
    version = aws_launch_template.eks_node[0].latest_version
  }

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "extra"
  }

  # The three worker-node policy attachments (worker-node/CNI/ECR-pull) that
  # used to be listed here now live in the security layer, already attached
  # to var.eks_node_role_arn before this module ever runs (same apply-order
  # reasoning as the cluster role above) -- not expressible as depends_on
  # across states, so they're dropped from this list rather than left dangling.
  depends_on = [
    aws_security_group_rule.node_ingress_kubelet_from_cluster_primary,
    aws_launch_template.eks_node
  ]
}

# IRSA: Pods cannot use the node role via IMDS by default (hop limit 1). Use a dedicated role for the backend SA.
data "tls_certificate" "eks_oidc" {
  count = var.enabled ? 1 : 0
  url   = aws_eks_cluster.expense[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.enabled ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.expense[0].identity[0].oidc[0].issuer

  tags = {
    Name = "${var.name_prefix}-eks-oidc"
  }
}

# eks_expense_ddb permission policy now owned by the security layer
# (terraform-security/) -- see var.eks_expense_backend_ddb_policy_arn.
resource "aws_iam_role" "eks_expense_backend_irsa" {
  count = var.enabled ? 1 : 0

  name = "${var.name_prefix}-eks-expense-backend-sa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks[0].arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.expense[0].identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.eks_expense_backend_sa_namespace}:${var.eks_expense_backend_sa_name}"
          "${replace(aws_eks_cluster.expense[0].identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.name_prefix}-eks-expense-backend-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "eks_expense_backend_irsa_ddb" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.eks_expense_backend_irsa[0].name
  policy_arn = var.eks_expense_backend_ddb_policy_arn
}

# SSM publish for this moved out to environments/{env}/compute/main.tf.

# Step 4: AWS Load Balancer Controller — IRSA
#
# The controller runs as a Pod inside the cluster (kube-system namespace) and
# calls AWS APIs to create/update ALBs, target groups, listener rules, and SGs
# on behalf of your Ingress resources.  It needs an IAM role it can assume via
# OIDC (IRSA), just like the backend Pod does for DynamoDB.
#
# ServiceAccount name "aws-load-balancer-controller" in namespace "kube-system"
# is the default expected by the official Helm chart — keep this in sync with
# Step 5 when we install the chart.

locals {
  oidc_issuer_url = var.enabled ? replace(aws_eks_cluster.expense[0].identity[0].oidc[0].issuer, "https://", "") : ""
}

# aws_lbc permission policy now owned by the security layer
# (terraform-security/) -- see var.aws_lbc_policy_arn.

resource "aws_iam_role" "aws_lbc" {
  count = var.enabled ? 1 : 0

  name = "${var.name_prefix}-aws-lbc"

  # Trust policy: only the aws-load-balancer-controller ServiceAccount in
  # kube-system may assume this role (OIDC / IRSA).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks[0].arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_issuer_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.name_prefix}-aws-lbc-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.aws_lbc[0].name
  policy_arn = var.aws_lbc_policy_arn
}

# Step 5: CloudWatch Observability — logs (Fluent Bit) + Container Insights metrics (CloudWatch Agent).
# EKS addon deploys both DaemonSets into the amazon-cloudwatch namespace; CloudWatchAgentServerPolicy
# covers both (it already includes logs:PutLogEvents / CreateLogGroup / CreateLogStream).
# "performance" added 2026-09-16: the addon creates this one itself (enhanced-
# observability process/accelerated-compute metrics) even though it was never
# declared here -- confirmed live, it survived a full `terraform destroy` and
# needed manual cleanup in the console. Declaring it here brings it under
# Terraform so future destroys catch it too.
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = var.enabled ? toset(["application", "host", "dataplane", "performance"]) : []

  name              = "/aws/containerinsights/${local.cluster_name}/${each.key}"
  retention_in_days = 14
}

resource "aws_iam_role" "cloudwatch_observability" {
  count = var.enabled ? 1 : 0

  name = "${var.name_prefix}-eks-cloudwatch-observability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks[0].arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_url}:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "${local.oidc_issuer_url}:sub" = "system:serviceaccount:amazon-cloudwatch:*"
        }
      }
    }]
  })

  tags = {
    Name = "${var.name_prefix}-eks-cloudwatch-observability-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.cloudwatch_observability[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.expense[0].name
  addon_name                  = "amazon-cloudwatch-observability"
  service_account_role_arn    = aws_iam_role.cloudwatch_observability[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.expense_default,
    aws_eks_node_group.expense_apps,
    aws_cloudwatch_log_group.container_insights,
  ]
}

# Step 6: VPC CNI — adopt the self-managed default install as a real EKS addon so
# NetworkPolicy enforcement can actually be turned on. Confirmed live (2026-09-24)
# that this cluster's aws-node DaemonSet ships with the network-policy nodeagent
# container present but started with `--enable-network-policy=false` -- AWS's
# out-of-the-box default. Every `NetworkPolicy` object in `gitops/network-policies/`
# was applying successfully (kubectl accepted them) but doing NOTHING: a live
# cross-namespace connectivity test (team-payments -> team-fraud-detection, a port
# with no allow-baseline rule covering it) succeeded when it should have timed out.
# No IRSA role needed here (unlike cloudwatch_observability) -- policy enforcement
# is a local per-node eBPF dataplane feature, it doesn't call any AWS API.
resource "aws_eks_addon" "vpc_cni" {
  count = var.enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.expense[0].name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  depends_on = [
    aws_eks_node_group.expense_default,
    aws_eks_node_group.expense_apps,
  ]
}

# SSM publish for this moved out to environments/{env}/compute/main.tf.
