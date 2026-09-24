variable "name_prefix" {
  description = "Prefix for resource names. This module is instantiated once for the whole account (see account/budget-alert), not per environment."
  type        = string
}

variable "budget_alert_email" {
  type    = string
  default = ""
}

variable "budget_monthly_usd" {
  type = number
}

variable "enable_aws_budget" {
  type    = bool
  default = false
}
