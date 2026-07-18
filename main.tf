resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  display_name   = var.display_name
  cidr_blocks    = var.cidr_blocks
  dns_label      = var.dns_label
  is_ipv6enabled = var.is_ipv6enabled

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}
