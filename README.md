# terraform-oci-vcn

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
Virtual Cloud Network (VCN). It creates a single VCN and exposes the OCIDs of the
default route table, security list and DHCP options so companion modules
(subnets, gateways, route tables) can build on top of it.

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

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| oci       | >= 5.0   |

## Inputs

| Name             | Description                                                        | Type           | Default              | Required |
|------------------|--------------------------------------------------------------------|----------------|----------------------|:--------:|
| `compartment_id` | OCID of the compartment in which to create the VCN.                | `string`       | n/a                  |   yes    |
| `display_name`   | Human-readable name for the VCN.                                   | `string`       | n/a                  |   yes    |
| `cidr_blocks`    | List of IPv4 CIDR blocks assigned to the VCN.                      | `list(string)` | `["10.0.0.0/16"]`    |    no    |
| `dns_label`      | DNS label for the VCN. Null disables the VCN DNS resolver.         | `string`       | `null`               |    no    |
| `is_ipv6enabled` | Enable IPv6 using an Oracle-allocated /56 prefix.                  | `bool`         | `false`              |    no    |
| `freeform_tags`  | Free-form tags applied to the VCN.                                 | `map(string)`  | `{}`                 |    no    |
| `defined_tags`   | Defined tags applied to the VCN, keyed as `namespace.key`.         | `map(string)`  | `{}`                 |    no    |

## Outputs

| Name                       | Description                                             |
|----------------------------|---------------------------------------------------------|
| `id`                       | OCID of the VCN.                                        |
| `cidr_blocks`              | IPv4 CIDR blocks assigned to the VCN.                   |
| `ipv6_cidr_blocks`         | IPv6 CIDR blocks assigned to the VCN, if enabled.       |
| `default_route_table_id`   | OCID of the VCN's default route table.                  |
| `default_security_list_id` | OCID of the VCN's default security list.                |
| `default_dhcp_options_id`  | OCID of the VCN's default set of DHCP options.          |
| `vcn_domain_name`          | Internal domain name of the VCN, if a dns_label was set.|

## License

[MIT](LICENSE)
