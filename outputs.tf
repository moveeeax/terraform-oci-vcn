output "id" {
  description = "OCID of the VCN."
  value       = oci_core_vcn.this.id
}

output "cidr_blocks" {
  description = "IPv4 CIDR blocks assigned to the VCN."
  value       = oci_core_vcn.this.cidr_blocks
}

output "ipv6_cidr_blocks" {
  description = "IPv6 CIDR blocks assigned to the VCN, if IPv6 is enabled."
  value       = oci_core_vcn.this.ipv6cidr_blocks
}

output "default_route_table_id" {
  description = "OCID of the VCN's default route table."
  value       = oci_core_vcn.this.default_route_table_id
}

output "default_security_list_id" {
  description = "OCID of the VCN's default security list."
  value       = oci_core_vcn.this.default_security_list_id
}

output "default_dhcp_options_id" {
  description = "OCID of the VCN's default set of DHCP options."
  value       = oci_core_vcn.this.default_dhcp_options_id
}

output "vcn_domain_name" {
  description = "Internal domain name of the VCN, if a dns_label was set."
  value       = oci_core_vcn.this.vcn_domain_name
}

output "flow_log_id" {
  description = "OCID of the VCN flow log, or null when flow logs are disabled."
  value       = one(oci_logging_log.flow_logs[*].id)
}

output "flow_log_group_id" {
  description = "OCID of the log group holding the VCN flow log, or null when flow logs are disabled."
  value       = var.enable_flow_logs ? local.flow_logs_log_group_id : null
}
