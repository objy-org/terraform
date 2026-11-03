# OBJY DB on Hetzner Cloud

This root module installs a fixed OBJY DB cluster on Hetzner Cloud.

It creates:

- one server and persistent WAL volume per shard replica
- a private network for peer traffic
- a spread placement group per shard
- a firewall and public load balancer
- a private Hetzner Object Storage bucket when no bucket is supplied
- the initial global shard map
- systemd-managed OBJY DB processes installed by cloud-init

## Prerequisites

- Terraform 1.7+ or a compatible OpenTofu release
- a Hetzner Cloud API token exposed as `HCLOUD_TOKEN`
- Hetzner Object Storage S3 credentials
- an immutable OBJY DB release URL and SHA-256 checksum

Object Storage credentials are sensitive Terraform variables:

```sh
export TF_VAR_s3_access_key="..."
export TF_VAR_s3_secret_key="..."
```

Copy `terraform.tfvars.example`, set the release information, and apply:

```sh
terraform init
terraform plan -out objydb.tfplan
terraform apply objydb.tfplan
```

After cloud-init finishes, `terraform output endpoint` prints the public HTTP
endpoint. Node startup can be inspected from a server with:

```sh
journalctl -u objydb.service -f
cloud-init status --long
```

The bootstrap targets Ubuntu images with Netplan. It explicitly enables DHCP
on Hetzner's first private interface (`enp7s0` or `ens10`) because Terraform
attaches that interface after the server has started. The load balancer reaches
the node over this private interface. Application config files are written only
after cloud-init creates the `objydb` user and group.

If an existing node has a running service but remains unhealthy in the load
balancer, check `ip -br addr`. On CX23, an unconfigured `enp7s0` can be repaired
persistently from the server console with:

```sh
netplan set ethernets.enp7s0.dhcp4=true
netplan apply
```

Bootstrap changes alter server `user_data` and can cause Terraform to propose
server replacement. Review the next plan even after repairing a node in place.

## Configure with environment variables

Terraform reads `TF_VAR_<name>` as the value of the matching input variable in
[`variables.tf`](variables.tf). Names are case-sensitive: use `TF_VAR_heap_mb`,
for example, not `TF_VAR_HEAP_MB`. This works when running Terraform directly
from this directory, including from a CI job.

For a new deployment configured entirely through the environment, use the
following Bash or Zsh example. Replace the credential and release placeholders
with real values. Do not copy `terraform.tfvars.example` for this workflow;
if a variable file already exists, remove or comment out any assignments that
would override these environment variables.

```sh
# Run from the repository's hetzner directory.
export HCLOUD_TOKEN="<hetzner-cloud-api-token>"
export TF_VAR_s3_access_key="<object-storage-access-key>"
export TF_VAR_s3_secret_key="<object-storage-secret-key>"

export TF_VAR_deployment_name="objydb-production"
export TF_VAR_location="fsn1"
export TF_VAR_server_type="ccx33"
export TF_VAR_shards=2
export TF_VAR_replicas=3
export TF_VAR_heap_mb=4096
export TF_VAR_wal_volume_size_gb=20

export TF_VAR_release_url="https://releases.example.com/objydb/objydb-linux-x64.tar.gz"
export TF_VAR_release_sha256="<64-character-lowercase-sha256>"
export TF_VAR_release_format="bundle"

export TF_VAR_s3_endpoint="https://fsn1.your-objectstorage.com"
export TF_VAR_s3_region="fsn1"

terraform init
terraform plan -out=objydb.tfplan
# Review the plan before applying it.
terraform apply objydb.tfplan
terraform output endpoint
```

`HCLOUD_TOKEN` is the Hetzner provider's authentication variable; it does not use
the `TF_VAR_` prefix. The release URL and checksum must identify a real release.
For a source archive, set `TF_VAR_release_format="github-source"` and follow the
[source-release requirements](#try-the-objy-release) below.

The main sizing and location settings are:

| Environment variable | Meaning | Default |
| --- | --- | --- |
| `TF_VAR_shards` | Number of shards; integer from 1 to 64 | `1` |
| `TF_VAR_replicas` | Total copies per shard; integer from 1 to 10 | `1` |
| `TF_VAR_heap_mb` | Maximum database V8 heap per node in MB; integer of at least 512 | `4096` |
| `TF_VAR_server_type` | Hetzner machine type for every database node | `ccx33` |
| `TF_VAR_wal_volume_size_gb` | Persistent WAL volume size per node in GB; integer of at least 10 | `10` |
| `TF_VAR_location` | Hetzner Cloud location for servers, volumes and load balancer | `fsn1` |
| `TF_VAR_s3_endpoint` | HTTPS Object Storage endpoint | `https://fsn1.your-objectstorage.com` |
| `TF_VAR_s3_region` | Object Storage location | `fsn1` |

There is no separate `node_count` input: **nodes = shards × replicas**. The
example creates six database nodes, with three copies of each of two shards.
`replicas=1` means one copy per shard, not one additional copy. The private subnet
must have enough addresses for the selected topology.

Database heap and machine RAM are different settings. Choose a `server_type`
with enough RAM for the heap, other process memory, and the operating system.
The standalone module does not automatically select a machine from `heap_mb`.

Other declared inputs use the same convention, for example
`TF_VAR_s3_bucket` to reuse an existing bucket. For lists and objects, use a
JSON value with shell quoting:

```sh
export TF_VAR_ssh_allowed_cidrs='["203.0.113.10/32"]'
export TF_VAR_labels='{"environment":"production"}'
```

On Windows PowerShell, use `$env:TF_VAR_shards = "2"` instead of
`export TF_VAR_shards=2`, and the same syntax for the other variables.
Terraform does not automatically load a `.env` file; export its values into the
process environment first. Exports affect commands launched from that shell;
use `unset TF_VAR_shards` in Bash/Zsh to remove an override.

### Which value wins?

For local Terraform CLI runs, precedence is highest to lowest:

1. Command-line `-var` and `-var-file` arguments, in the order supplied.
2. `*.auto.tfvars` and `*.auto.tfvars.json` files, in lexical order.
3. `terraform.tfvars.json`.
4. `terraform.tfvars`.
5. `TF_VAR_*` environment variables.
6. Defaults declared in `variables.tf`.

For example, `shards = 1` in `terraform.tfvars` overrides
`export TF_VAR_shards=2`. Remove or comment out the file assignment to use the
environment value. Likewise, `-var-file=objy-release.hcl` overrides environment
values for settings that file supplies. See Terraform's
[input-variable documentation](https://developer.hashicorp.com/terraform/language/values/variables#assign-values-to-variables).

A saved plan captures the selected values. Changing environment variables after
`terraform plan -out=objydb.tfplan` does not change that plan; generate and review
a new plan to use new values. Environment changes alone do not modify a running
cluster. This standalone module still has the [lifecycle limitations](#safety)
below; setting variables is not an automated resizing workflow.

These examples do not configure ObjyDB Control Center. It uses the separate
`installer/hetzner` module, generates a variable file from its wizard, and filters
inherited `TF_VAR_*` variables. Configure Control Center clusters through its
supported UI/CLI flow.

## Try the objy release

`objy-release.hcl` configures one CX23 node with one shard, one replica, a 2 GiB
V8 heap, and a 10 GB WAL volume in Falkenstein. It also creates the load balancer
and a private Object Storage bucket. Set the three credential environment
variables above, then run from this directory:

```sh
terraform init
terraform plan -var-file=objy-release.hcl -out=objydb.tfplan
terraform apply objydb.tfplan
terraform output endpoint
terraform output -raw admin_password
```

The `objy` release currently contains source archives only. This configuration
pins its source commit and SHA-256 checksum and uses `release_format = "github-source"`.
Cloud-init verifies and extracts the source, verifies and installs the pinned
Node.js runtime, and runs `npm ci --omit=dev --ignore-scripts` using the included
lockfile. Nodes need outbound HTTPS access to GitHub, nodejs.org, and the npm
registry during bootstrap. The default runtime is Linux x64; use a matching
`node_runtime` URL/checksum if selecting an ARM server.

The default `release_format = "bundle"` continues to accept a ready-to-run archive
with `bin/node`, dependencies, and `src/index.js` directly at its root.
GitHub source archives must have one top-level directory, which the installer strips.
Do not use npm package tarballs without a lockfile in source mode.

This is an HTTP trial endpoint. The bucket and shard-map object retain their
existing destruction protection, so a plain `terraform destroy` cannot tear down
the entire trial. The HCL is an input file for this updated module, not a standalone
Terraform module.

## Safety

Terraform state contains bootstrap secrets and must be protected like a secret.
The generated Object Storage bucket and shard-map object are protected against
Terraform destruction. The first development version uses the configured
Terraform backend; configure protected remote state before production use.

Changing replica count is not yet automated. Changing shard count requires an
offline reshard workflow and is intentionally rejected by the operating model
of this first module.
