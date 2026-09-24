output "eks_cluster_name" {
  value = var.enabled ? aws_eks_cluster.expense[0].name : null
}

output "eks_status" {
  value = var.enabled ? aws_eks_cluster.expense[0].status : null
}

output "eks_cluster_endpoint" {
  value = var.enabled ? aws_eks_cluster.expense[0].endpoint : null
}

output "eks_node_group_name" {
  value = var.enabled ? aws_eks_node_group.expense_default[0].node_group_name : null
}

output "eks_node_group_apps_name" {
  value = var.enabled ? aws_eks_node_group.expense_apps[0].node_group_name : null
}

output "eks_expense_backend_irsa_role_arn" {
  description = "IRSA role ARN for the expense-backend ServiceAccount. Published to SSM by the caller (environments/{env}/compute), not by this module."
  value       = var.enabled ? aws_iam_role.eks_expense_backend_irsa[0].arn : null
}

output "eks_cluster_additional_security_group_id" {
  description = "Extra SG attached to EKS control plane ENIs (vpc_config.security_group_ids)."
  value       = var.enabled ? aws_security_group.eks_cluster_additional[0].id : null
}

output "eks_cluster_primary_security_group_id" {
  description = "EKS-managed cluster primary SG (nodes must include this when using a custom node SG)."
  value       = var.enabled ? aws_eks_cluster.expense[0].vpc_config[0].cluster_security_group_id : null
}

output "eks_node_security_group_id" {
  description = "Worker node SG attached via launch template (plus cluster primary SG)."
  value       = var.enabled ? aws_security_group.eks_node[0].id : null
}

output "aws_lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller Helm chart. Published to SSM by the caller (environments/{env}/compute), not by this module."
  value       = var.enabled ? aws_iam_role.aws_lbc[0].arn : null
}

output "eks_alb_security_group_id" {
  description = "ALB SG ID — pass to Ingress annotation alb.ingress.kubernetes.io/security-groups."
  value       = var.enabled ? aws_security_group.eks_alb[0].id : null
}
