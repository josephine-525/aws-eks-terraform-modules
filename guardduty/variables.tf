variable "enable" {
  type    = bool
  default = true
}

variable "finding_publishing_frequency" {
  description = "How often GuardDuty exports findings to CloudWatch Events / EventBridge. One of FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  type        = string
  default     = "SIX_HOURS"
}

variable "enable_s3_protection" {
  description = "Monitor S3 data-plane events (GetObject/PutObject/etc.) for anomalous access."
  type        = bool
  default     = true
}

variable "enable_eks_protection" {
  description = "Monitor EKS audit logs for anomalous API activity."
  type        = bool
  default     = true
}
