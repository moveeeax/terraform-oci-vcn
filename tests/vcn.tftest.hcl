# Unit tests for the module, run against a mocked OCI provider so they need no
# credentials and no network: `terraform test` (or `tofu test`).
#
# NOTE: mock_provider requires Terraform >= 1.7 / OpenTofu >= 1.7 to *run* the
# tests. The module itself still supports >= 1.5; do not raise required_version
# in versions.tf for this.

mock_provider "oci" {}

variables {
  compartment_id = "ocid1.compartment.oc1..aaaaaaaaexamplecompartment"
  display_name   = "unit-test-vcn"
}

run "default_security_list_is_locked_down" {
  command = plan

  assert {
    condition     = length(oci_core_default_security_list.this) == 1
    error_message = "The VCN's default security list must be adopted by default, otherwise OCI's built-in SSH-from-0.0.0.0/0 rule survives."
  }

  assert {
    condition     = length(oci_core_default_security_list.this[0].ingress_security_rules) == 0
    error_message = "The managed default security list must have no ingress rules unless the caller asks for them."
  }

  assert {
    condition     = length(oci_core_default_security_list.this[0].egress_security_rules) == 0
    error_message = "The managed default security list must have no egress rules unless the caller asks for them."
  }
}

run "default_security_list_management_can_be_disabled" {
  command = plan

  variables {
    manage_default_security_list = false
  }

  assert {
    condition     = length(oci_core_default_security_list.this) == 0
    error_message = "manage_default_security_list = false must leave the default security list unmanaged."
  }
}

run "default_security_list_rules_are_passed_through" {
  command = plan

  variables {
    default_security_list_ingress_rules = [
      {
        protocol    = "6"
        source      = "10.0.0.0/16"
        description = "SSH from inside the VCN only"
        tcp_options = { min = 22, max = 22 }
      }
    ]
    default_security_list_egress_rules = [
      {
        protocol    = "all"
        destination = "0.0.0.0/0"
      }
    ]
  }

  assert {
    condition     = length(oci_core_default_security_list.this[0].ingress_security_rules) == 1
    error_message = "Ingress rules supplied by the caller must reach the default security list."
  }

  assert {
    condition = one([
      for r in oci_core_default_security_list.this[0].ingress_security_rules : r.source
    ]) == "10.0.0.0/16"
    error_message = "The ingress rule source must be passed through unchanged."
  }

  assert {
    condition = one([
      for r in oci_core_default_security_list.this[0].ingress_security_rules : r.tcp_options[0].max
    ]) == 22
    error_message = "Nested tcp_options must be passed through unchanged."
  }

  assert {
    condition     = length(oci_core_default_security_list.this[0].egress_security_rules) == 1
    error_message = "Egress rules supplied by the caller must reach the default security list."
  }
}

run "flow_logs_are_off_by_default" {
  command = plan

  assert {
    condition     = length(oci_logging_log.flow_logs) == 0 && length(oci_logging_log_group.flow_logs) == 0
    error_message = "Flow logs must not be created unless enable_flow_logs is set."
  }
}

run "flow_logs_create_a_log_and_a_group" {
  variables {
    enable_flow_logs             = true
    flow_logs_retention_duration = 180
  }

  assert {
    condition     = length(oci_logging_log_group.flow_logs) == 1
    error_message = "Enabling flow logs must create a log group when none is supplied."
  }

  assert {
    condition     = oci_logging_log.flow_logs[0].configuration[0].source[0].service == "flowlogs"
    error_message = "The flow log must point at the flowlogs service."
  }

  assert {
    condition     = oci_logging_log.flow_logs[0].configuration[0].source[0].resource == oci_core_vcn.this.id
    error_message = "The flow log source must be this VCN."
  }

  assert {
    condition     = oci_logging_log.flow_logs[0].log_group_id == oci_logging_log_group.flow_logs[0].id
    error_message = "The flow log must live in the log group the module created."
  }

  assert {
    condition     = oci_logging_log.flow_logs[0].retention_duration == 180
    error_message = "retention_duration must be passed through unchanged."
  }

  assert {
    condition     = output.flow_log_id == oci_logging_log.flow_logs[0].id
    error_message = "The flow_log_id output must expose the created flow log."
  }
}

run "flow_logs_reuse_an_existing_log_group" {
  command = plan

  variables {
    enable_flow_logs       = true
    flow_logs_log_group_id = "ocid1.loggroup.oc1..aaaaaaaaexampleloggroup"
  }

  assert {
    condition     = length(oci_logging_log_group.flow_logs) == 0
    error_message = "No log group must be created when the caller supplies one."
  }

  assert {
    condition     = oci_logging_log.flow_logs[0].log_group_id == "ocid1.loggroup.oc1..aaaaaaaaexampleloggroup"
    error_message = "The supplied log group OCID must be used."
  }
}

run "rejects_malformed_cidr" {
  command = plan

  variables {
    cidr_blocks = ["not-a-cidr"]
  }

  expect_failures = [var.cidr_blocks]
}

run "rejects_cidr_prefix_shorter_than_16" {
  command = plan

  variables {
    cidr_blocks = ["10.0.0.0/8"]
  }

  expect_failures = [var.cidr_blocks]
}

run "rejects_cidr_prefix_longer_than_30" {
  command = plan

  variables {
    cidr_blocks = ["10.0.0.0/31"]
  }

  expect_failures = [var.cidr_blocks]
}

run "rejects_cidr_with_host_bits_set" {
  command = plan

  variables {
    cidr_blocks = ["10.0.0.5/16"]
  }

  expect_failures = [var.cidr_blocks]
}

run "rejects_empty_cidr_list" {
  command = plan

  variables {
    cidr_blocks = []
  }

  expect_failures = [var.cidr_blocks]
}

run "accepts_multiple_valid_cidrs" {
  command = plan

  variables {
    cidr_blocks = ["10.0.0.0/16", "192.168.16.0/20", "172.16.0.0/30"]
  }

  assert {
    condition     = length(oci_core_vcn.this.cidr_blocks) == 3
    error_message = "Valid CIDR blocks must be accepted and passed through."
  }
}

run "rejects_dns_label_with_hyphen" {
  command = plan

  variables {
    dns_label = "prod-vcn"
  }

  expect_failures = [var.dns_label]
}

run "rejects_dns_label_starting_with_digit" {
  command = plan

  variables {
    dns_label = "1prod"
  }

  expect_failures = [var.dns_label]
}

run "rejects_dns_label_longer_than_15_chars" {
  command = plan

  variables {
    dns_label = "abcdefghijklmnop"
  }

  expect_failures = [var.dns_label]
}

run "accepts_valid_dns_label" {
  command = plan

  variables {
    dns_label = "prodvcn01"
  }

  assert {
    condition     = oci_core_vcn.this.dns_label == "prodvcn01"
    error_message = "A valid dns_label must be passed through unchanged."
  }
}

run "accepts_null_dns_label" {
  command = plan

  variables {
    dns_label = null
  }

  # dns_label is optional+computed in the provider, so the planned value is not
  # observable here; reaching a successful plan at all is the assertion that
  # matters -- a null label must not trip the dns_label validation.
  assert {
    condition     = oci_core_vcn.this.compartment_id == var.compartment_id
    error_message = "A null dns_label must be allowed and must plan cleanly."
  }
}

run "rejects_invalid_flow_log_retention" {
  command = plan

  variables {
    enable_flow_logs             = true
    flow_logs_retention_duration = 45
  }

  expect_failures = [var.flow_logs_retention_duration]
}
