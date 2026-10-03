variable "name_prefix" {
  description = "Prefix for resource names. Set by the caller (environments/{env}/security) -- this module doesn't know what environment it's in."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the expenses DynamoDB table this environment's expense-backend Pod needs access to. Passed in by the caller, which read it from its own environment's db layer via SSM -- this module never touches SSM itself."
  type        = string
}
