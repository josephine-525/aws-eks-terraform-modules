# Convenience only, for local `terraform output`. The real interface other
# layers consume is the SSM parameters in ssm.tf.
output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  value = aws_iam_role.eks_node_group.arn
}

output "eks_expense_backend_ddb_policy_arn" {
  value = aws_iam_policy.eks_expense_ddb.arn
}

output "aws_lbc_policy_arn" {
  value = aws_iam_policy.aws_lbc.arn
}
