# terraform-oci-vcn

Terraform module that manages an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/)
Virtual Cloud Network (VCN). It creates a single VCN, closes down the default
security list OCI ships with it, optionally adds an internet gateway and a NAT
gateway together with the route tables that make them usable, optionally turns
on VCN flow logs, and exposes the OCIDs of the default route table, security
list and DHCP options so companion modules (subnets, route tables) can build on
top of it.

## Usage

```hcl
module "vcn" {
  source = "github.com/moveeeax/terraform-oci-vcn?ref=v1.0.0"

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
  source = "github.com/moveeeax/terraform-oci-vcn?ref=v1.0.0"

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

## Gateways

The module used to have two companions, `terraform-oci-internet-gateway` and
`terraform-oci-nat-gateway`; both are archived and their scope lives here.
Both gateways are off by default and turned on by setting an object:

```hcl
module "vcn" {
  # ...
  internet_gateway = {}
  nat_gateway = {
    reserve_public_ip = true
  }
}

resource "oci_core_subnet" "public" {
  # ...
  route_table_id = module.vcn.public_route_table_id
}

resource "oci_core_subnet" "private" {
  # ...
  prohibit_public_ip_on_vnic = true
  route_table_id             = module.vcn.private_route_table_id
}
```

A gateway on its own routes nothing: a subnet reaches the internet only once
its route table sends the default route to the gateway, and its security lists
or NSGs allow the traffic. So by default the module also creates

- a public route table (`public_route_table_id`) with `0.0.0.0/0`, plus `::/0`
  when `is_ipv6enabled = true`, pointing at the internet gateway;
- a private route table (`private_route_table_id`) with `0.0.0.0/0` pointing at
  the NAT gateway. OCI does not route IPv6 through a NAT gateway.

Set `create_route_table = false` on either object to skip its route table and
write the rules yourself. The route tables are not attached to any subnet; that
stays with whoever creates the subnets. Security rules are not touched either.

`internet_gateway` attributes:

| Attribute                  | Description                                                                                  | Type     | Default              |
|----------------------------|----------------------------------------------------------------------------------------------|----------|----------------------|
| `display_name`             | Gateway name.                                                                                | `string` | `<display_name>-igw` |
| `enabled`                  | Whether the gateway passes traffic. A disabled gateway applies cleanly and blackholes traffic. | `bool`   | `true`               |
| `route_table_id`           | Ingress route table for traffic arriving through the gateway (transit routing). Not the subnet route table. Null uses the VCN default. | `string` | `null` |
| `create_route_table`       | Create the public route table with the default route to the gateway.                         | `bool`   | `true`               |
| `route_table_display_name` | Public route table name.                                                                     | `string` | `<display_name>-public` |

`nat_gateway` attributes:

| Attribute                  | Description                                                                                  | Type     | Default              |
|----------------------------|----------------------------------------------------------------------------------------------|----------|----------------------|
| `display_name`             | Gateway name.                                                                                | `string` | `<display_name>-nat` |
| `block_traffic`            | Break-glass switch: OCI drops all traffic through the gateway while routes still point at it. | `bool`   | `false`              |
| `reserve_public_ip`        | Create a reserved public IP and assign it to the gateway. See below.                         | `bool`   | `false`              |
| `public_ip_id`             | Reserved public IP managed elsewhere. Mutually exclusive with `reserve_public_ip`.           | `string` | `null`               |
| `route_table_id`           | Route table the gateway itself uses (transit routing). Null uses the VCN default.            | `string` | `null`               |
| `create_route_table`       | Create the private route table with the default route to the gateway.                        | `bool`   | `true`               |
| `route_table_display_name` | Private route table name.                                                                    | `string` | `<display_name>-private` |

OCID inputs are checked for the expected prefix (`ocid1.routetable.`,
`ocid1.publicip.`), so a transposed OCID fails at plan time.

### NAT egress IP

With neither `reserve_public_ip` nor `public_ip_id`, OCI gives the NAT gateway
an ephemeral public IP that changes whenever the gateway is recreated. If a
partner allow-lists your egress address, set `reserve_public_ip = true`: the
module creates an `oci_core_public_ip` with `lifetime = "RESERVED"` and assigns
it to the gateway, so the address survives a gateway recreate. `nat_ip` reports
the address either way.

That reserved IP is in this module's state. Removing `nat_gateway`, turning
`reserve_public_ip` off or destroying the module deletes it, and the address goes back to Oracle's pool. A module cannot make `prevent_destroy` depend on an
input, so when the address must outlive the module, create it in the root
configuration with `prevent_destroy` and pass its OCID instead:

```hcl
resource "oci_core_public_ip" "nat" {
  compartment_id = var.compartment_id
  lifetime       = "RESERVED"
  display_name   = "prod-nat-ip"

  lifecycle {
    prevent_destroy = true
  }
}

module "vcn" {
  # ...
  nat_gateway = {
    public_ip_id = oci_core_public_ip.nat.id
  }
}
```

### Migrating from the archived modules

Keep the existing gateways by moving them in state instead of recreating them
(a NAT gateway recreated without a reserved IP gets a new address):

```hcl
moved {
  from = module.internet_gateway.oci_core_internet_gateway.this
  to   = module.vcn.oci_core_internet_gateway.this[0]
}

moved {
  from = module.nat_gateway.oci_core_nat_gateway.this
  to   = module.vcn.oci_core_nat_gateway.this[0]
}
```

Set `display_name` in the objects to the names the gateways already have, or
the next apply renames them.

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
| `flow_logs_retention_duration`         | Flow log retention in days, in 30-day increments from 30 to 180.                                             | `number`        | `90`              |    no    |
| `internet_gateway`                     | Internet gateway and its public route table. Null creates none. See [Gateways](#gateways).                   | `object`        | `null`            |    no    |
| `nat_gateway`                          | NAT gateway, its private route table and optional reserved IP. Null creates none. See [Gateways](#gateways). | `object`        | `null`            |    no    |
| `freeform_tags`                        | Free-form tags applied to the created resources.                                                             | `map(string)`   | `{}`              |    no    |
| `defined_tags`                         | Defined tags applied to the created resources, keyed as `namespace.key`.                                     | `map(string)`   | `{}`              |    no    |

Security rule objects accept:

| Attribute                        | Ingress | Egress | Type                                        |
|----------------------------------|:-------:|:------:|---------------------------------------------|
| `protocol`                       |   yes   |  yes   | `string` — `"all"`, `"1"` (ICMP), `"6"` (TCP), `"17"` (UDP), `"58"` (ICMPv6) |
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
| `internet_gateway_id`      | OCID of the internet gateway, or null.                   |
| `public_route_table_id`    | OCID of the route table sending the default route to the internet gateway, or null. |
| `nat_gateway_id`           | OCID of the NAT gateway, or null.                        |
| `nat_ip`                   | Public IP the NAT gateway uses for outbound traffic, or null. |
| `nat_public_ip_id`         | OCID of the reserved public IP the module created for the NAT gateway, or null. |
| `private_route_table_id`   | OCID of the route table sending the default route to the NAT gateway, or null. |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test          # mocked provider, no credentials or network needed
```

## License

[MIT](LICENSE)
