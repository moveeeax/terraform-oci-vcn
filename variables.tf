variable "compartment_id" {
  description = "OCID of the compartment in which to create the VCN."
  type        = string
}

variable "display_name" {
  description = "Human-readable name for the VCN."
  type        = string
}

variable "cidr_blocks" {
  description = "List of IPv4 CIDR blocks assigned to the VCN. OCI accepts prefix lengths between /16 and /30."
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.cidr_blocks) > 0
    error_message = "At least one CIDR block must be provided."
  }

  validation {
    condition     = alltrue([for c in var.cidr_blocks : can(cidrhost(c, 0))])
    error_message = "Every entry in cidr_blocks must be a valid IPv4 CIDR block, for example \"10.0.0.0/16\"."
  }

  validation {
    # OCI rejects anything outside /16../30 at apply time, long after the plan
    # looked fine, so catch it here instead.
    condition     = alltrue([for c in var.cidr_blocks : can(regex("^[0-9.]+/(1[6-9]|2[0-9]|30)$", c))])
    error_message = "OCI requires every VCN CIDR block to have a prefix length between /16 and /30."
  }

  validation {
    # 10.0.0.5/16 is not a network address; OCI refuses it.
    condition     = alltrue([for c in var.cidr_blocks : can(cidrhost(c, 0)) ? cidrhost(c, 0) == split("/", c)[0] : true])
    error_message = "Every entry in cidr_blocks must be a network address with all host bits zero, for example \"10.0.0.0/16\" rather than \"10.0.0.5/16\"."
  }
}

variable "dns_label" {
  description = "DNS label for the VCN, used to form the VCN domain name. Must start with a letter and contain only letters and digits, max 15 characters. Null disables the VCN DNS resolver."
  type        = string
  default     = null

  validation {
    # OCI only rejects a malformed label at apply time; fail during plan.
    condition     = var.dns_label == null || can(regex("^[a-zA-Z][a-zA-Z0-9]{0,14}$", var.dns_label))
    error_message = "dns_label must start with a letter, contain only letters and digits (no hyphens, underscores or dots) and be at most 15 characters long."
  }
}

variable "is_ipv6enabled" {
  description = "Whether to enable IPv6 for the VCN using an Oracle-allocated /56 prefix."
  type        = bool
  default     = false
}

variable "manage_default_security_list" {
  description = "Whether the module manages the default security list that OCI creates with the VCN. Leaving it unmanaged keeps Oracle's built-in rules, which allow SSH from 0.0.0.0/0."
  type        = bool
  default     = true
}

variable "default_security_list_ingress_rules" {
  description = "Ingress rules for the VCN's default security list. Empty (the default) means the default security list allows no inbound traffic at all. Only used when manage_default_security_list is true."
  type = list(object({
    protocol     = string
    source       = string
    source_type  = optional(string)
    description  = optional(string)
    stateless    = optional(bool)
    tcp_options  = optional(object({ min = optional(number), max = optional(number) }))
    udp_options  = optional(object({ min = optional(number), max = optional(number) }))
    icmp_options = optional(object({ type = number, code = optional(number) }))
  }))
  default = []
}

variable "default_security_list_egress_rules" {
  description = "Egress rules for the VCN's default security list. Empty (the default) means the default security list allows no outbound traffic at all. Only used when manage_default_security_list is true."
  type = list(object({
    protocol         = string
    destination      = string
    destination_type = optional(string)
    description      = optional(string)
    stateless        = optional(bool)
    tcp_options      = optional(object({ min = optional(number), max = optional(number) }))
    udp_options      = optional(object({ min = optional(number), max = optional(number) }))
    icmp_options     = optional(object({ type = number, code = optional(number) }))
  }))
  default = []
}

variable "enable_flow_logs" {
  description = "Whether to enable VCN flow logs through the OCI Logging service. Requires the Logging service to be usable by the caller's IAM policies."
  type        = bool
  default     = false
}

variable "flow_logs_log_group_id" {
  description = "OCID of an existing log group to hold the VCN flow log. Null creates a log group alongside the VCN. Only used when enable_flow_logs is true."
  type        = string
  default     = null
}

variable "flow_logs_retention_duration" {
  description = "Retention period in days for the VCN flow log. OCI accepts 30-day increments from 30 to 180."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180], var.flow_logs_retention_duration)
    error_message = "flow_logs_retention_duration must be one of 30, 60, 90, 120, 150 or 180 days."
  }
}

variable "freeform_tags" {
  description = "Free-form tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to every resource the module creates, keyed as \"namespace.key\"."
  type        = map(string)
  default     = {}
}

variable "internet_gateway" {
  description = <<-EOT
    Internet gateway for the VCN. Null (the default) creates none. When set, the
    module creates the gateway and, unless create_route_table is false, a public
    route table that sends 0.0.0.0/0 (and ::/0 when IPv6 is enabled) to it; attach
    that route table to public subnets. route_table_id is the ingress route table
    for traffic arriving through the gateway (transit routing), not the subnet route
    table; null uses the VCN default.
  EOT
  type = object({
    display_name             = optional(string)
    enabled                  = optional(bool, true)
    route_table_id           = optional(string)
    create_route_table       = optional(bool, true)
    route_table_display_name = optional(string)
  })
  default = null

  validation {
    condition = (
      var.internet_gateway == null
      ? true
      : var.internet_gateway.route_table_id == null || can(regex("^ocid1\\.routetable\\.", var.internet_gateway.route_table_id))
    )
    error_message = "internet_gateway.route_table_id must be null or a route table OCID (starting with \"ocid1.routetable.\")."
  }
}

variable "nat_gateway" {
  description = <<-EOT
    NAT gateway for the VCN. Null (the default) creates none. When set, the module
    creates the gateway and, unless create_route_table is false, a private route
    table that sends 0.0.0.0/0 to it; attach that route table to private subnets.
    reserve_public_ip = true also creates a reserved public IP and assigns it to the
    gateway, so the egress address survives a gateway recreate. public_ip_id assigns
    a reserved public IP managed elsewhere instead; the two are mutually exclusive.
    Null for both lets Oracle allocate an ephemeral IP. block_traffic = true makes
    OCI drop all traffic through the gateway. route_table_id is the route table the
    gateway itself uses (transit routing); null uses the VCN default.
  EOT
  type = object({
    display_name             = optional(string)
    block_traffic            = optional(bool, false)
    reserve_public_ip        = optional(bool, false)
    public_ip_id             = optional(string)
    route_table_id           = optional(string)
    create_route_table       = optional(bool, true)
    route_table_display_name = optional(string)
  })
  default = null

  validation {
    condition = (
      var.nat_gateway == null
      ? true
      : var.nat_gateway.public_ip_id == null || can(regex("^ocid1\\.publicip\\.", var.nat_gateway.public_ip_id))
    )
    error_message = "nat_gateway.public_ip_id must be null or a reserved public IP OCID (starting with \"ocid1.publicip.\")."
  }

  validation {
    condition = (
      var.nat_gateway == null
      ? true
      : !(var.nat_gateway.reserve_public_ip && var.nat_gateway.public_ip_id != null)
    )
    error_message = "Set either nat_gateway.reserve_public_ip or nat_gateway.public_ip_id, not both."
  }

  validation {
    condition = (
      var.nat_gateway == null
      ? true
      : var.nat_gateway.route_table_id == null || can(regex("^ocid1\\.routetable\\.", var.nat_gateway.route_table_id))
    )
    error_message = "nat_gateway.route_table_id must be null or a route table OCID (starting with \"ocid1.routetable.\")."
  }
}
