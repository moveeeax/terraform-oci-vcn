variable "compartment_id" {
  description = "OCID of the compartment in which to create the VCN."
  type        = string
}

variable "display_name" {
  description = "Human-readable name for the VCN."
  type        = string
}

variable "cidr_blocks" {
  description = "List of IPv4 CIDR blocks assigned to the VCN."
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.cidr_blocks) > 0
    error_message = "At least one CIDR block must be provided."
  }
}

variable "dns_label" {
  description = "DNS label for the VCN, used to form the VCN domain name. Null disables the VCN DNS resolver."
  type        = string
  default     = null
}

variable "is_ipv6enabled" {
  description = "Whether to enable IPv6 for the VCN using an Oracle-allocated /56 prefix."
  type        = bool
  default     = false
}

variable "freeform_tags" {
  description = "Free-form tags applied to the VCN."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to the VCN, keyed as \"namespace.key\"."
  type        = map(string)
  default     = {}
}
