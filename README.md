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

The module requires an immutable OBJY DB Linux release archive. The archive
must contain `bin/node` and the application entrypoint `src/index.js` at its
root. Set its HTTPS URL and SHA-256 checksum in `terraform.tfvars`.

This first version installs a fixed topology. Do not change `shards` on an
existing deployment; safe reshard orchestration will be added separately.
