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

## Safety

Terraform state contains bootstrap secrets and must be protected like a secret.
The generated Object Storage bucket and shard-map object are protected against
Terraform destruction. The first development version uses the configured
Terraform backend; configure protected remote state before production use.

Changing replica count is not yet automated. Changing shard count requires an
offline reshard workflow and is intentionally rejected by the operating model
of this first module.
