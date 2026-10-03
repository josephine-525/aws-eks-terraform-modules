variable "enabled" {
  type = bool
}

variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from the network layer (read from SSM by the root config)."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs from the network layer, one per AZ."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from the network layer, one per AZ. Node groups are pinned one-per-index (see aws_eks_node_group resources) to guarantee AZ spread."
}

variable "eks_kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "eks_node_desired_size" {
  type    = number
  default = 1
}

variable "eks_node_min_size" {
  type    = number
  default = 1
}

variable "eks_node_max_size" {
  type    = number
  default = 2
}

variable "eks_cluster_role_arn" {
  type        = string
  description = "IAM role for the EKS control plane (eks.amazonaws.com trust). Set by the caller (environments/{env}/compute), which read its own environment's security layer output via SSM. This module never touches SSM itself."
}

variable "eks_node_role_arn" {
  type        = string
  description = "IAM role for EKS worker nodes (ec2.amazonaws.com trust). Set by the caller (environments/{env}/compute), which read its own environment's security layer output via SSM. This module never touches SSM itself."
}

variable "eks_expense_backend_ddb_policy_arn" {
  type        = string
  description = "Least-privilege DynamoDB policy for the expense-backend IRSA role. Policy document owned by the security layer; the role itself (federated to this cluster's OIDC provider) stays here since it can't exist before the cluster does."
}

variable "aws_lbc_policy_arn" {
  type        = string
  description = "AWS Load Balancer Controller IAM policy (static AWS doc). Policy document owned by the security layer; the role itself (IRSA) stays here for the same OIDC-coupling reason as above."
}

variable "eks_admin_principal_arn" {
  type        = string
  description = "IAM principal for EKS API access entry (human kubectl). Empty skips."
  default     = ""
}

variable "eks_ci_principal_arn" {
  type        = string
  description = "IAM principal for CI automation kubectl (deploy-eks job). Empty skips. If same as eks_admin_principal_arn, only one entry is created."
  default     = ""
}

variable "eks_expense_backend_sa_namespace" {
  type        = string
  description = "Kubernetes namespace of the ServiceAccount the expense-backend IRSA role's trust policy is scoped to (its OIDC \"sub\" condition). No default: this used to be hardcoded to \"expense\" inside this module, which silently broke IRSA auth (AssumeRoleWithWebIdentity AccessDenied) the moment a caller's real ServiceAccount lived in a different namespace — every caller must now set this explicitly instead of inheriting a guessed value."
}

variable "eks_expense_backend_sa_name" {
  type        = string
  description = "Name of the ServiceAccount the expense-backend IRSA role's trust policy is scoped to (its OIDC \"sub\" condition). No default, same reasoning as eks_expense_backend_sa_namespace — this used to be hardcoded to \"expense-backend\", which only matched the old expenseinfra/terraform project's hand-written ServiceAccount name, not a Helm-chart-generated one like \"team-payments-backend-common-web-service\"."
}

