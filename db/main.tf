resource "aws_dynamodb_table" "expenses" {
  name         = "${var.name_prefix}-expenses"
  billing_mode = var.billing_mode
  hash_key     = "user_id"
  range_key    = "expense_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "expense_id"
    type = "S"
  }
}
