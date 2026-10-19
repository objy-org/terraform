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
