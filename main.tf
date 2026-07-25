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
