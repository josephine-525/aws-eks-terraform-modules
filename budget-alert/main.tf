data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "budget_alerts" {
  name = "${var.name_prefix}-budget-alerts"
}

resource "aws_sns_topic_subscription" "budget_email" {
  count = var.budget_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

resource "aws_budgets_budget" "monthly" {
  count = var.enable_aws_budget ? 1 : 0

  account_id        = data.aws_caller_identity.current.account_id
  name              = "${var.name_prefix}-month-usd"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_monthly_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"
  time_period_end   = "2087-01-01_00:00"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}
