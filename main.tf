resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  display_name   = var.display_name
  cidr_blocks    = var.cidr_blocks
  dns_label      = var.dns_label
  is_ipv6enabled = var.is_ipv6enabled

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

# OCI creates a default security list together with every VCN, and that list
# ships with rules that allow SSH (TCP 22) from 0.0.0.0/0 and ICMP from the
# internet. Terraform does not manage it unless it is explicitly adopted, so
# leaving it alone silently keeps an internet-reachable SSH rule in the VCN.
# Adopting it here makes the rule set an explicit module input that defaults to
# empty (deny everything); callers that want rules on it can pass them in, or
# set manage_default_security_list = false to opt out entirely.
resource "oci_core_default_security_list" "this" {
  count = var.manage_default_security_list ? 1 : 0

  manage_default_resource_id = oci_core_vcn.this.default_security_list_id
  display_name               = "${var.display_name}-default"

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  dynamic "ingress_security_rules" {
    for_each = var.default_security_list_ingress_rules

    content {
      protocol    = ingress_security_rules.value.protocol
      source      = ingress_security_rules.value.source
      source_type = ingress_security_rules.value.source_type
      description = ingress_security_rules.value.description
      stateless   = ingress_security_rules.value.stateless

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.tcp_options == null ? [] : [ingress_security_rules.value.tcp_options]

        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.udp_options == null ? [] : [ingress_security_rules.value.udp_options]

        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }

      dynamic "icmp_options" {
        for_each = ingress_security_rules.value.icmp_options == null ? [] : [ingress_security_rules.value.icmp_options]

        content {
          type = icmp_options.value.type
          code = icmp_options.value.code
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = var.default_security_list_egress_rules

    content {
      protocol         = egress_security_rules.value.protocol
      destination      = egress_security_rules.value.destination
      destination_type = egress_security_rules.value.destination_type
      description      = egress_security_rules.value.description
      stateless        = egress_security_rules.value.stateless

      dynamic "tcp_options" {
        for_each = egress_security_rules.value.tcp_options == null ? [] : [egress_security_rules.value.tcp_options]

        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }

      dynamic "udp_options" {
        for_each = egress_security_rules.value.udp_options == null ? [] : [egress_security_rules.value.udp_options]

        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }

      dynamic "icmp_options" {
        for_each = egress_security_rules.value.icmp_options == null ? [] : [egress_security_rules.value.icmp_options]

        content {
          type = icmp_options.value.type
          code = icmp_options.value.code
        }
      }
    }
  }
}

# VCN flow logs. OCI models them as a Logging service log whose source is the
# VCN itself, and that log needs a log group to live in; create one unless the
# caller already has a group to use.
resource "oci_logging_log_group" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_log_group_id == null ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${var.display_name}-flow-logs"
  description    = "Flow logs for VCN ${var.display_name}."

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_logging_log" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  display_name       = "${var.display_name}-flow-logs"
  log_group_id       = local.flow_logs_log_group_id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.flow_logs_retention_duration

  configuration {
    compartment_id = var.compartment_id

    source {
      category    = "all"
      resource    = oci_core_vcn.this.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
  }

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

locals {
  flow_logs_log_group_id = (
    var.flow_logs_log_group_id != null
    ? var.flow_logs_log_group_id
    : one(oci_logging_log_group.flow_logs[*].id)
  )
}

# Internet gateway. On its own it routes nothing: a subnet only reaches the
# internet once its route table sends 0.0.0.0/0 to the gateway, which is the
# step people forget, so the module also creates that public route table unless
# told not to.
resource "oci_core_internet_gateway" "this" {
  count = var.internet_gateway == null ? 0 : 1

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = coalesce(var.internet_gateway.display_name, "${var.display_name}-igw")
  enabled        = var.internet_gateway.enabled
  route_table_id = var.internet_gateway.route_table_id

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_core_route_table" "public" {
  count = var.internet_gateway != null && try(var.internet_gateway.create_route_table, false) ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = coalesce(var.internet_gateway.route_table_display_name, "${var.display_name}-public")

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this[0].id
    description       = "IPv4 default route to the internet gateway."
  }

  # IPv6 egress goes through the internet gateway too: an IPv6 route rule can
  # only target an internet gateway or a DRG, never a NAT gateway.
  dynamic "route_rules" {
    for_each = var.is_ipv6enabled ? [1] : []

    content {
      destination       = "::/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_internet_gateway.this[0].id
      description       = "IPv6 default route to the internet gateway."
    }
  }

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

# Reserved public IP for the NAT gateway. Partners allow-list the egress
# address, and an ephemeral one changes whenever the gateway is recreated. The
# IP lives in this module's state, so dropping nat_gateway or turning
# reserve_public_ip off releases it; callers who need it to outlive the module
# create it themselves (with prevent_destroy) and pass public_ip_id instead.
resource "oci_core_public_ip" "nat" {
  count = var.nat_gateway != null && try(var.nat_gateway.reserve_public_ip, false) ? 1 : 0

  compartment_id = var.compartment_id
  lifetime       = "RESERVED"
  display_name   = "${coalesce(var.nat_gateway.display_name, "${var.display_name}-nat")}-ip"

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_core_nat_gateway" "this" {
  count = var.nat_gateway == null ? 0 : 1

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = coalesce(var.nat_gateway.display_name, "${var.display_name}-nat")
  block_traffic  = var.nat_gateway.block_traffic
  public_ip_id   = var.nat_gateway.reserve_public_ip ? oci_core_public_ip.nat[0].id : var.nat_gateway.public_ip_id
  route_table_id = var.nat_gateway.route_table_id

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_core_route_table" "private" {
  count = var.nat_gateway != null && try(var.nat_gateway.create_route_table, false) ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = coalesce(var.nat_gateway.route_table_display_name, "${var.display_name}-private")

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this[0].id
    description       = "IPv4 default route to the NAT gateway."
  }

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}
