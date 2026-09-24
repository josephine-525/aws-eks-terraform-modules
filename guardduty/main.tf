resource "aws_guardduty_detector" "this" {
  enable                       = var.enable
  finding_publishing_frequency = var.finding_publishing_frequency
}

# aws_guardduty_detector's own `datasources` block is deprecated in the AWS
# provider in favor of one aws_guardduty_detector_feature resource per
# protection plan -- lets each be toggled independently instead of one big
# nested block.
resource "aws_guardduty_detector_feature" "s3_data_events" {
  detector_id = aws_guardduty_detector.this.id
  name        = "S3_DATA_EVENTS"
  status      = var.enable_s3_protection ? "ENABLED" : "DISABLED"
}

# The natural pairing with this account's EKS cluster: monitors EKS audit
# logs for anomalous API calls (privilege escalation attempts, etc.).
resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  detector_id = aws_guardduty_detector.this.id
  name        = "EKS_AUDIT_LOGS"
  status      = var.enable_eks_protection ? "ENABLED" : "DISABLED"
}
