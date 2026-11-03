# ObjyDB on Hetzner

**Shards, replicas, storage. One public endpoint.**

Each database node gets a server and persistent WAL volume. Terraform connects
them over a private network, adds an HTTP load balancer and configures Object Storage.

## Quick start

You need **Terraform 1.7+**, a Hetzner Cloud token, Object Storage credentials,
and an ObjyDB Linux release URL with its SHA-256 checksum.

### Configure with environment variables

Run from the repository root in Bash or Zsh. Replace the `<...>` placeholders.
If you already have variable files, remove duplicate settings first—they override
the environment.

```sh
cd hetzner

# Credentials
export HCLOUD_TOKEN="<cloud-token>"
export TF_VAR_s3_access_key="<storage-access-key>"
export TF_VAR_s3_secret_key="<storage-secret-key>"

# Cluster: 2 shards × 3 copies = 6 nodes
export TF_VAR_shards=2
export TF_VAR_replicas=3
export TF_VAR_heap_mb=4096
export TF_VAR_server_type="ccx33"
export TF_VAR_location="fsn1"
export TF_VAR_wal_volume_size_gb=20

# Ready-to-run release bundle
export TF_VAR_release_url="<https-release-url>"
export TF_VAR_release_sha256="<64-character-lowercase-sha256>"

terraform init
terraform plan -out=objydb.tfplan
# Review the plan before applying.
terraform apply objydb.tfplan
terraform output endpoint
```

The bundle must contain `bin/node`, dependencies and `src/index.js` at its root.
For the pinned `objy` source release, use the [trial instructions](REFERENCE.md#trial-release).

## Size your cluster

| Environment variable | Controls | Default |
| --- | --- | --- |
| `TF_VAR_shards` | Shards | `1` |
| `TF_VAR_replicas` | Total copies of each shard | `1` |
| `TF_VAR_heap_mb` | Maximum database heap per node, MB | `4096` |
| `TF_VAR_server_type` | Machine size per node | `ccx33` |
| `TF_VAR_wal_volume_size_gb` | WAL disk per node, GB | `10` |
| `TF_VAR_location` | Cloud location | `fsn1` |

**Nodes = shards × replicas.** There is no separate node-count setting.
Choose a machine with RAM to spare beyond the database heap; increasing
`heap_mb` does not automatically select a larger machine.

Any input in [variables.tf](variables.tf) accepts `TF_VAR_<name>`, including
`s3_endpoint`, `s3_region` and `s3_bucket`. Names are case-sensitive.

## Three things to know

- **Files win.** `terraform.tfvars`, `*.auto.tfvars` and CLI `-var` / `-var-file`
  values override the environment. Remove duplicate assignments to use exports.
- **Plans are snapshots.** After changing variables, generate a new plan.
  Terraform does not load `.env` files automatically.
- **This is initial setup.** Changing shards or replicas is not a supported
  standalone resizing workflow. Control Center uses a separate module and
  ignores inherited `TF_VAR_*` settings.

Keep Terraform state private: it contains secrets. The bucket and shard-map
object have destruction protection, so `terraform destroy` cannot remove the
entire deployment.

[Release & troubleshooting reference](REFERENCE.md) · [Example variable file](terraform.tfvars.example)
