variable "name_prefix" {
  description = "Prefix for resource names. Set by the caller (environments/{env}/db) -- this module doesn't know what environment it's in."
  type        = string
}

variable "billing_mode" {
  type    = string
  default = "PAY_PER_REQUEST"
}
