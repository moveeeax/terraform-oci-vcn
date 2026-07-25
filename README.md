# terraform-oci-vcn

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
Virtual Cloud Network (VCN). It creates a single VCN, closes down the default
security list OCI ships with it, optionally turns on VCN flow logs, and exposes
the OCIDs of the default route table, security list and DHCP options so
companion modules (subnets, gateways, route tables) can build on top of it.

## Usage

```hcl
module "vcn" {
  source = "github.com/moveeeax/terraform-oci-vcn"

  compartment_id = var.compartment_id
  display_name   = "prod-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "prod"

  freeform_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Security defaults

OCI creates a **default security list** along with every VCN, pre-populated with
rules that allow **SSH (TCP 22) from `0.0.0.0/0`** and ICMP from the internet.
Terraform does not touch that list unless it is explicitly adopted, so a module
that only creates the VCN leaves an internet-reachable SSH rule behind for every
subnet that uses the default list.

This module adopts the default security list (`manage_default_security_list`,
`true` by default) and drives its rules from
`default_security_list_ingress_rules` / `default_security_list_egress_rules`,
both of which default to empty — so out of the box the default security list
permits nothing. Add the rules you actually want:

```hcl
module "vcn" {
  source = "github.com/moveeeax/terraform-oci-vcn"

  compartment_id = var.compartment_id
  display_name   = "prod-vcn"
  cidr_blocks    = ["10.0.0.0/16"]

  default_security_list_ingress_rules = [
    {
      protocol    = "6" # TCP
      source      = "10.0.0.0/16"
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
}
```

Set `manage_default_security_list = false` to leave the list entirely to
something else — note that this keeps Oracle's built-in open-SSH rule.

## Flow logs

`enable_flow_logs = true` creates an OCI Logging log for the VCN (service
`flowlogs`, category `all`) and, unless `flow_logs_log_group_id` is supplied, a
log group to hold it. The caller's IAM policies must allow use of the Logging
service in the target compartment.

```hcl
module "vcn" {
  # ...
  enable_flow_logs             = true
  flow_logs_retention_duration = 180
}
```

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| oci       | >= 5.0   |

Running the test suite (`terraform test` / `tofu test`) additionally needs
Terraform or OpenTofu >= 1.7 for `mock_provider`; the module itself still works
on 1.5.

## Inputs

| Name                                  | Description                                                                                                  | Type            | Default           | Required |
|---------------------------------------|--------------------------------------------------------------------------------------------------------------|-----------------|-------------------|:--------:|
| `compartment_id`                       | OCID of the compartment in which to create the VCN.                                                          | `string`        | n/a               |   yes    |
| `display_name`                         | Human-readable name for the VCN.                                                                             | `string`        | n/a               |   yes    |
| `cidr_blocks`                          | IPv4 CIDR blocks assigned to the VCN. Validated: real CIDRs, prefix `/16`–`/30`, host bits zero.              | `list(string)`  | `["10.0.0.0/16"]` |    no    |
| `dns_label`                            | DNS label for the VCN. Validated: starts with a letter, letters and digits only, max 15 chars. Null disables the VCN DNS resolver. | `string`        | `null`            |    no    |
| `is_ipv6enabled`                       | Enable IPv6 using an Oracle-allocated /56 prefix.                                                            | `bool`          | `false`           |    no    |
| `manage_default_security_list`         | Whether the module manages the default security list OCI creates with the VCN.                               | `bool`          | `true`            |    no    |
| `default_security_list_ingress_rules`  | Ingress rules for the default security list. Empty means no inbound traffic is allowed.                      | `list(object)`  | `[]`              |    no    |
| `default_security_list_egress_rules`   | Egress rules for the default security list. Empty means no outbound traffic is allowed.                      | `list(object)`  | `[]`              |    no    |
| `enable_flow_logs`                     | Enable VCN flow logs through the OCI Logging service.                                                        | `bool`          | `false`           |    no    |
| `flow_logs_log_group_id`               | Existing log group OCID for the flow log. Null creates one.                                                  | `string`        | `null`            |    no    |
| `flow_logs_retention_duration`         | Flow log retention in days, in 30-day increments from 30 to 360.                                             | `number`        | `90`              |    no    |
| `freeform_tags`                        | Free-form tags applied to the created resources.                                                             | `map(string)`   | `{}`              |    no    |
| `defined_tags`                         | Defined tags applied to the created resources, keyed as `namespace.key`.                                     | `map(string)`   | `{}`              |    no    |

Security rule objects accept:

| Attribute                        | Ingress | Egress | Type                                        |
|----------------------------------|:-------:|:------:|---------------------------------------------|
| `protocol`                       |   yes   |  yes   | `string` — `"all"`, `"1"` (ICMP), `"6"` (TCP), `"17"` (UDP) |
| `source` / `destination`         | `source` | `destination` | `string`                            |
| `source_type` / `destination_type` | `source_type` | `destination_type` | `string` (optional)      |
| `description`                    |   yes   |  yes   | `string` (optional)                          |
| `stateless`                      |   yes   |  yes   | `bool` (optional)                            |
| `tcp_options` / `udp_options`    |   yes   |  yes   | `object({ min, max })` (optional)            |
| `icmp_options`                   |   yes   |  yes   | `object({ type, code })` (optional)          |

## Outputs

| Name                       | Description                                              |
|----------------------------|----------------------------------------------------------|
| `id`                       | OCID of the VCN.                                         |
| `cidr_blocks`              | IPv4 CIDR blocks assigned to the VCN.                    |
| `ipv6_cidr_blocks`         | IPv6 CIDR blocks assigned to the VCN, if enabled.        |
| `default_route_table_id`   | OCID of the VCN's default route table.                   |
| `default_security_list_id` | OCID of the VCN's default security list.                 |
| `default_dhcp_options_id`  | OCID of the VCN's default set of DHCP options.           |
| `vcn_domain_name`          | Internal domain name of the VCN, if a dns_label was set. |
| `flow_log_id`              | OCID of the VCN flow log, or null when disabled.         |
| `flow_log_group_id`        | OCID of the log group holding the flow log, or null.     |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test          # mocked provider, no credentials or network needed
```

## License

[MIT](LICENSE)
