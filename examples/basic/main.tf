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
