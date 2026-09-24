# No env-specific values here or anywhere else in this module -- every value
# that should differ between dev/staging/prod comes in as a variable, set by
# whichever environments/{env}/network/terraform.tfvars calls this module.
variable "name_prefix" {
  description = "Prefix for resource names. The caller (environments/{env}/network) decides what this is -- this module has no idea what environment it's being used in."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Three public subnet CIDRs (one per AZ)."
  type        = list(string)
  default     = ["10.40.0.0/20", "10.40.16.0/20", "10.40.32.0/20"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 3
    error_message = "public_subnet_cidrs must contain exactly 3 CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "Three private subnet CIDRs (one per AZ)."
  type        = list(string)
  default     = ["10.40.128.0/20", "10.40.144.0/20", "10.40.160.0/20"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 3
    error_message = "private_subnet_cidrs must contain exactly 3 CIDR blocks."
  }
}
