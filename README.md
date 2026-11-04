# OBJY DB Terraform

Terraform deployment configurations for OBJY DB across cloud platforms.

Each platform has its own Terraform files and a chapter here: **Deploy** with a
ready-to-use preset, or **Customize** the settings. Hetzner is the first supported
platform; more will follow.

*[Terraform installation guide](https://developer.hashicorp.com/terraform/install)*

## Hetzner

**Shards, replicas, storage. One public endpoint.**

Each node gets a server and persistent WAL volume, connected through a private
network, an HTTP load balancer and Object Storage.

### 1. Get your API token

> [!IMPORTANT]
> **You'll need a Hetzner API token.** Open [Hetzner Console](https://console.hetzner.com/projects),
> select your project, then go to **Security → API tokens → Generate API token**.
> Choose **Read & Write** permissions and copy the token into `HCLOUD_TOKEN` below.

### 2. Choose your size

Choose a preset. The release URL, checksums, machine sizes and storage settings
are already filled in—you only supply credentials.

| Preset | Nodes | Shards × copies | Machine/node | Heap/node | WAL/node |
| --- | --- | --- | --- | --- | --- |
| [Tiny](hetzner/objy-tiny.hcl) | 1 | 1 × 1 | CX23 | 2 GiB | 10 GB |
| [Small](hetzner/objy-small.hcl) | 3 | 1 × 3 | CX23 | 2 GiB | 10 GB |
| [Medium](hetzner/objy-medium.hcl) | 6 | 2 × 3 | CX33 | 4 GiB | 20 GB |
| [Large](hetzner/objy-large.hcl) | 12 | 4 × 3 | CX43 | 8 GiB | 40 GB |

All four use the checksum-pinned [OBJY DB `v0.1.0` release](https://github.com/objy-org/objy/releases/tag/v0.1.0)
and the same Node.js runtime in Falkenstein (`fsn1`). These are HTTP
configurations intended for testing; Hetzner capacity and account quotas still
apply.

### 3. Deploy

You need **Terraform 1.7+** and **Hetzner Object Storage credentials**, in addition
to the cloud token above. Run from the repository root in Bash or Zsh:

```sh
cd hetzner
export HCLOUD_TOKEN="<cloud-token>"
export TF_VAR_s3_access_key="<storage-access-key>"
export TF_VAR_s3_secret_key="<storage-secret-key>"

terraform init
terraform workspace new my-cluster
terraform plan -var-file=objy-tiny.hcl -out=objydb.tfplan
# Review the plan before applying.
terraform apply objydb.tfplan
terraform output endpoint
terraform output -raw admin_password
```

For another size, replace `objy-tiny.hcl` with `objy-small.hcl`,
`objy-medium.hcl` or `objy-large.hcl`. Use one workspace per cluster; return to
this cluster with `terraform workspace select my-cluster`. Choose the size before
creating it—switching presets is not a resizing workflow.

### Remove a cluster

OBJY DB protects its Object Storage bucket and shard map from accidental
Terraform deletion. Back up the workspace state, detach those protected storage
resources, then destroy the remaining infrastructure:

```sh
cd hetzner
terraform workspace select my-cluster
terraform state pull > my-cluster.tfstate.backup
terraform state rm minio_s3_object.shard_map
# Run this only when it appears in `terraform state list`:
terraform state rm 'minio_s3_bucket.data[0]'
terraform plan -destroy -var-file=objy-tiny.hcl -out=objydb-destroy.tfplan
# Review the destructive plan before applying it.
terraform apply objydb-destroy.tfplan
terraform workspace select default
terraform workspace delete my-cluster
```

Use the same preset or custom variables used to create the cluster. This removes
Terraform-managed compute, networking and WAL volumes while leaving Object
Storage data in place. Delete the bucket separately only after verifying that
its snapshots and journals are no longer needed. Protect the state backup: it
contains sensitive deployment values.

### Customize

For a new custom cluster, start in `hetzner/` with the three credential exports
above. Set the inputs yourself instead of passing a preset file:

```sh
export TF_VAR_deployment_name="objydb-custom"
export TF_VAR_shards=2
export TF_VAR_replicas=3
export TF_VAR_heap_mb=4096
export TF_VAR_server_type="ccx33"
export TF_VAR_location="fsn1"
export TF_VAR_wal_volume_size_gb=20

# Supply your own ready-to-run release bundle.
export TF_VAR_release_format="bundle"
export TF_VAR_release_url="<https-release-url>"
export TF_VAR_release_sha256="<64-character-lowercase-sha256>"

terraform init
terraform workspace new my-custom-cluster
terraform plan -out=objydb.tfplan
# Review the plan before applying.
terraform apply objydb.tfplan
terraform output endpoint
```

The bundle must contain `bin/node`, dependencies and `src/index.js` at its root.
For source archives, see **More options** below.

#### Cluster settings

| Environment variable | Controls | Default |
| --- | --- | --- |
| `TF_VAR_shards` | Shards | `1` |
| `TF_VAR_replicas` | Total copies of each shard | `1` |
| `TF_VAR_heap_mb` | Maximum database heap per node, MB | `4096` |
| `TF_VAR_server_type` | Machine size per node | `ccx33` |
| `TF_VAR_wal_volume_size_gb` | WAL disk per node, GB | `10` |
| `TF_VAR_location` | Cloud location | `fsn1` |

**Nodes = shards × replicas.** Choose a machine with RAM to spare beyond the
heap; increasing `heap_mb` does not automatically select a larger machine.

Any input in [hetzner/variables.tf](hetzner/variables.tf) accepts `TF_VAR_<name>`,
including `s3_endpoint`, `s3_region` and `s3_bucket`. Names are case-sensitive.
Prefer files? Start with [terraform.tfvars.example](hetzner/terraform.tfvars.example).

### More options

<details>
<summary>Source releases, PowerShell and other variables</summary>

Set `TF_VAR_release_format="github-source"` for an archive containing source and
an npm lockfile inside one top-level directory. Bootstrap verifies the archive
and pinned Node.js runtime, then runs `npm ci --omit=dev --ignore-scripts`.
Nodes need HTTPS access to GitHub, nodejs.org and npm. The default runtime is
Linux x64; ARM servers need a matching `node_runtime` URL and checksum.

PowerShell uses `$env:TF_VAR_shards = "2"` instead of `export TF_VAR_shards=2`.
For lists and objects in Bash/Zsh, quote JSON:

```sh
export TF_VAR_ssh_allowed_cidrs='["203.0.113.10/32"]'
export TF_VAR_labels='{"environment":"production"}'
```

SSH access also requires `ssh_public_key`. Use `unset TF_VAR_shards` to remove
an export. See [Terraform's variable reference](https://developer.hashicorp.com/terraform/language/values/variables#assign-values-to-variables)
for full precedence rules.

</details>

<details>
<summary>Troubleshoot a node</summary>

From the server console, inspect startup and networking:

```sh
journalctl -u objydb.service -f
cloud-init status --long
ip -br addr
```

Bootstrap enables DHCP on the first private interface (`enp7s0` or `ens10`).
For an older CX23 node with an unconfigured `enp7s0`:

```sh
netplan set ethernets.enp7s0.dhcp4=true
netplan apply
```

Bootstrap changes can trigger server replacement; review the next plan.
A green load-balancer check alone does not confirm restoration: verify
`restore.status == "ready"` on every node.

</details>
