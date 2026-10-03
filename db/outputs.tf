output "table_name" {
  value = aws_dynamodb_table.expenses.name
}

output "table_arn" {
  value = aws_dynamodb_table.expenses.arn
}
