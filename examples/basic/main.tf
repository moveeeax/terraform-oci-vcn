terraform {
  required_version = ">= 1.5"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0"
    }
  }
}

provider "oci" {}

module "vcn" {
  source = "../.."

  compartment_id = var.compartment_id
  display_name   = "example-vcn"
  cidr_blocks    = ["10.10.0.0/16"]
  dns_label      = "example"

  # The default security list is managed by the module and is empty unless
  # rules are given here, so nothing inherits OCI's SSH-from-anywhere rule.
  default_security_list_ingress_rules = [
    {
      protocol    = "6" # TCP
      source      = "10.10.0.0/16"
      description = "SSH from inside the VCN only"
      tcp_options = { min = 22, max = 22 }
    }
  ]

  default_security_list_egress_rules = [
    {
      protocol    = "all"
      destination = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  ]

  enable_flow_logs = true

  freeform_tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

variable "compartment_id" {
  description = "Compartment OCID to deploy the example VCN into."
  type        = string
}

output "vcn_id" {
  value = module.vcn.id
}

output "flow_log_id" {
  value = module.vcn.flow_log_id
}
