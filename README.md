# OBJY DB Terraform

Terraform-compatible deployment packages for customer-owned OBJY DB clusters.

The first target is Hetzner Cloud. It creates a fixed sharded and replicated
cluster with private peer networking, persistent WAL volumes, Hetzner Object
Storage persistence, and one load-balanced public endpoint.

## Hetzner

```sh
cd hetzner
cp terraform.tfvars.example terraform.tfvars

export HCLOUD_TOKEN="..."
export TF_VAR_s3_access_key="..."
export TF_VAR_s3_secret_key="..."

terraform init
terraform plan
terraform apply
```

By default the module expects an OBJY DB Linux release archive containing
`bin/node`, its dependencies, and `src/index.js` at its root. It also supports
checksum-pinned GitHub source archives with `release_format = "github-source"`;
see the Hetzner README and `hetzner/objy-release.hcl` for the `objy` trial release.

This first version installs a fixed topology. Do not change `shards` on an
existing deployment; safe reshard orchestration will be added separately.

## Configure Terraform with environment variables

When running the standalone `hetzner` module directly, set `TF_VAR_<name>` to
supply any input declared in [`hetzner/variables.tf`](hetzner/variables.tf):

```sh
export TF_VAR_shards=2
export TF_VAR_replicas=3
export TF_VAR_heap_mb=4096
export TF_VAR_location=fsn1
export TF_VAR_wal_volume_size_gb=20
```

These settings describe six database nodes (two shards with three copies each),
a 4,096 MB maximum database heap per node, and a 20 GB WAL volume per node.
`TF_VAR_server_type` selects the Hetzner machine size separately; changing the
heap limit does not automatically choose a larger server.

**Variable files override environment variables.** If you copied
`terraform.tfvars.example` in the quick start, remove or comment out the settings
you want to supply through the environment. Command-line `-var` and `-var-file`
arguments also take precedence. See the [complete environment-variable guide](hetzner/README.md#configure-with-environment-variables)
for credentials, release inputs, supported settings, and plan/apply examples.

This applies to direct Terraform use. ObjyDB Control Center generates its own
variable file from the wizard and filters inherited `TF_VAR_*` variables; those
variables do not currently configure its UI or interactive CLI.

## Installer lifecycle and resizing

All lifecycle management stays in the separate installer and Terraform. Do not
modify OBJY DB or require a new database management API. The detailed
[implementation plan](../objy-db-installer/docs/cluster-lifecycle-plan.md) lives
in the installer repository and defines the contracts required of future cloud
integrations as well as Hetzner.

Use a planned maintenance window and a simple offline workflow: disable the
load balancer's client forwarding while retaining its identity/IP, stop the
cluster gracefully, resize its infrastructure with Terraform, publish the new
shard map and node configuration, restore, and reopen traffic. Verify that all
client ingress uses the gate and allow accepted work to finish. Keep traffic
disabled in every intermediate Terraform plan, so apply cannot reopen it.
Verify that every old node has shut down gracefully and flushed its WAL to
Object Storage before removing any node. Preserve the old map/data and retain
retired WAL volumes until the new cluster is verified. Keep database processes
stopped during infrastructure changes. For shard-layout changes, start every
target node in `persistence.restoreMode = "reshard"` against the new map.

Once restoration and the required primary checkpoints have succeeded, persist
`restoreMode = "scoped"` and use the existing restart-based finalization from
the installer. The current release caches this mode in memory and uses it
during runtime durable catch-up; editing the file alone only affects future
boots. This supersedes the earlier proposal to add a live mode switch inside
OBJY DB: database changes are explicitly out of scope. Keep traffic disabled
until all target nodes pass scoped restore, data and replica readiness checks.
Test a crash during restore, a crash after completion, and replica catch-up
after the replication log has been truncated against the unmodified release.

Changing only replica count preserves shard scopes and uses normal restore/catch-up. The separate installer now implements the coordinator and UI controls for `installer/hetzner`. Local fixtures pass; disposable live-cloud qualification remains outstanding. The standalone `hetzner` module above still installs a fixed topology and is not adopted by this workflow.

The objy release returns HTTP 200 from `/health` even during restore: readiness
must inspect `restore.status == "ready"` for every expected node. A successful
Terraform apply or a green LB check is not sufficient. Record migration phases
durably, resume safely after interruption, retain old resources on failure, keep
node addresses stable, and manage runtime configuration independently of
immutable cloud-init user data. The new `src/installer/lifecycle-service.js` in objy-db-installer is the integration point. Future providers must implement and qualify the same adapter contract before enabling lifecycle controls.
