# Hetzner reference

[← Quick start](README.md)

## Trial release

[objy-release.hcl](objy-release.hcl) pins the `objy` source release and configures
one CX23 node in Falkenstein: one shard, one copy, 2 GiB heap and a 10 GB WAL disk.

Export the three credentials from the quick start, then run in `hetzner/`:

```sh
terraform init
terraform plan -var-file=objy-release.hcl -out=objydb.tfplan
terraform apply objydb.tfplan
terraform output endpoint
terraform output -raw admin_password
```

Review the plan before applying. The trial file overrides environment values
for the settings it supplies. Its endpoint uses HTTP; use test data.

## Release formats

| `TF_VAR_release_format` | Archive contents |
| --- | --- |
| `bundle` (default) | `bin/node`, dependencies and `src/index.js` at the root |
| `github-source` | Source and an npm lockfile inside one top-level directory |

Source mode verifies the release and pinned Node.js runtime, then runs
`npm ci --omit=dev --ignore-scripts`. Nodes need HTTPS access to GitHub,
nodejs.org and the npm registry. The default runtime is Linux x64; ARM servers
need a matching `node_runtime` URL and checksum. npm package archives without
a lockfile are not supported in source mode.

## Variable tips

PowerShell uses `$env:TF_VAR_shards = "2"` instead of `export TF_VAR_shards=2`.
For lists and objects in Bash/Zsh, quote JSON:

```sh
export TF_VAR_ssh_allowed_cidrs='["203.0.113.10/32"]'
export TF_VAR_labels='{"environment":"production"}'
```

SSH access also requires `ssh_public_key`. Use `unset TF_VAR_shards` to remove
an export. For detailed precedence rules, see the
[Terraform variable reference](https://developer.hashicorp.com/terraform/language/values/variables#assign-values-to-variables).

## Node troubleshooting

From the server console, inspect startup and networking:

```sh
journalctl -u objydb.service -f
cloud-init status --long
ip -br addr
```

The Ubuntu bootstrap enables DHCP on the first private interface (`enp7s0` or
`ens10`). If an older CX23 node has an unconfigured `enp7s0`, repair it with:

```sh
netplan set ethernets.enp7s0.dhcp4=true
netplan apply
```

Bootstrap changes can trigger server replacement; inspect the next Terraform
plan. A green load-balancer check alone does not confirm restore completion:
check `restore.status == "ready"` on every node.

## State and lifecycle

Protect state and saved plans as secrets. Configure a protected remote backend
before production use. Bucket and shard-map destruction protection requires
separate, deliberate cleanup.

The standalone module does not coordinate resizing. Control Center's separate
[module contract](../installer/hetzner/README.md) describes its lifecycle workflow;
it does not adopt standalone deployments. See the
[lifecycle design](../../objy-db-installer/docs/cluster-lifecycle-plan.md) for
maintenance, restore and recovery details.
