# ObjyDB Terraform

Terraform deployment configurations for ObjyDB across cloud platforms.

This repository is organized by platform, each with its own Terraform files,
settings and deployment guide. Hetzner is the first supported platform; more
platforms will follow.

## 1. Hetzner

Deploy to Hetzner with private networking, persistent storage and a load-balanced
endpoint. Choose your cluster size; Terraform provisions the infrastructure.

### Deploy

| How you deploy | Where to start |
| --- | --- |
| Run Terraform yourself | [Hetzner quick start →](hetzner/README.md) |
| Use the Control Center wizard | [Control Center module →](installer/hetzner/README.md) |

### Choose your size

For direct Terraform deployments, use environment variables:

```sh
export TF_VAR_shards=2
export TF_VAR_replicas=3
export TF_VAR_heap_mb=4096
```

**6 nodes · 3 copies per shard · 4,096 MB heap per node.**

Set `TF_VAR_server_type` separately to choose the machine size. Variable files
and CLI flags override environment values. The [Hetzner guide](hetzner/README.md#configure-with-environment-variables)
includes credentials, release settings and deployment commands.

The standalone module creates a fixed topology. Control Center manages its own
configuration and lifecycle; it does not read inherited `TF_VAR_*` settings.
Its resizing workflow still needs live-cloud qualification.

[All Terraform inputs](hetzner/variables.tf) · [Lifecycle design](../objy-db-installer/docs/cluster-lifecycle-plan.md)
