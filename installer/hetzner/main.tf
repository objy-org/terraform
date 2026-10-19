terraform {
  required_version = ">= 1.7.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
  }
}

provider "hcloud" {}

variable "deployment_name" {
  type = string
  validation {
    condition     = can(regex("^odb-[a-f0-9]{12}$", var.deployment_name))
    error_message = "Expected an installer-generated cluster ID."
  }
}
variable "location" { type = string }
variable "server_type" { type = string }
variable "shards" {
  type = number
  validation {
    condition     = var.shards >= 1 && var.shards <= 32 && floor(var.shards) == var.shards
    error_message = "Shards must be an integer from 1 to 32."
  }
}
variable "replicas" {
  type = number
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 3 && floor(var.replicas) == var.replicas
    error_message = "Replicas must be an integer from 1 to 3."
  }
}
variable "protocol" {
  type = string
  validation {
    condition     = contains(["http", "https"], var.protocol)
    error_message = "Protocol must be http or https."
  }
}
variable "ssh_public_key" { type = string }
variable "bootstrap_script" { type = string }
variable "public_domain" {
  type    = string
  default = ""
}
variable "client_traffic_enabled" {
  type    = bool
  default = true
}
variable "node_addresses" {
  type    = map(string)
  default = {}
}
variable "node_volume_keys" {
  type    = map(string)
  default = {}
}
# Keep retired volumes in this registry until a separate, explicit cleanup.
variable "wal_volumes" {
  type    = map(object({ name = string }))
  default = null
}

locals {
  labels  = { objydb-deployment = var.deployment_name, objydb-managed-by = "terraform-installer-v1" }
  network = "10.42.0.0/24"
  nodes = { for node in flatten([
    for s in range(var.shards) : [for r in range(var.replicas) : {
      key   = "s${s + 1}-r${r + 1}", id = "${var.deployment_name}-s${s + 1}-r${r + 1}",
      shard = s, replica = r,
      ip    = lookup(var.node_addresses, "s${s + 1}-r${r + 1}", cidrhost(local.network, 10 + s * var.replicas + r))
    }]
  ]) : node.key => node }
  volumes     = var.wal_volumes != null ? var.wal_volumes : { for key, node in local.nodes : key => { name = "${node.id}-wal" } }
  volume_keys = { for key, node in local.nodes : key => lookup(var.node_volume_keys, key, key) }
}

resource "hcloud_ssh_key" "installer" {
  name       = var.deployment_name
  public_key = var.ssh_public_key
  labels     = local.labels
}
resource "hcloud_network" "cluster" {
  name     = var.deployment_name
  ip_range = local.network
  labels   = local.labels
}
resource "hcloud_network_subnet" "cluster" {
  network_id   = hcloud_network.cluster.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = local.network
}
resource "hcloud_firewall" "cluster" {
  name   = var.deployment_name
  labels = local.labels
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8080"
    source_ips = [local.network]
  }
}
resource "hcloud_placement_group" "shards" {
  for_each = toset([for s in range(var.shards) : tostring(s)])
  name     = "${var.deployment_name}-s${each.key}"
  type     = "spread"
  labels   = local.labels
}
resource "hcloud_volume" "wal" {
  depends_on = [hcloud_managed_certificate.cluster]
  for_each   = local.volumes
  name       = each.value.name
  size       = 10
  location   = var.location
  format     = "ext4"
  labels     = local.labels
  lifecycle { prevent_destroy = true }
}
resource "hcloud_server" "nodes" {
  for_each                 = local.nodes
  name                     = each.value.id
  server_type              = var.server_type
  image                    = "ubuntu-24.04"
  location                 = var.location
  ssh_keys                 = [hcloud_ssh_key.installer.id]
  firewall_ids             = [hcloud_firewall.cluster.id]
  placement_group_id       = hcloud_placement_group.shards[tostring(each.value.shard)].id
  shutdown_before_deletion = true
  labels                   = local.labels
  network {
    subnet_id = hcloud_network_subnet.cluster.id
    ip        = each.value.ip
    alias_ips = []
  }
  user_data = templatefile("${path.module}/bootstrap.yaml.tftpl", {
    script_base64 = base64encode(var.bootstrap_script)
    volume_id     = hcloud_volume.wal[local.volume_keys[each.key]].id
  })
  lifecycle {
    precondition {
      condition     = var.shards * var.replicas <= 64
      error_message = "At most 64 nodes are supported."
    }
  }
}
resource "hcloud_volume_attachment" "wal" {
  for_each  = local.nodes
  volume_id = hcloud_volume.wal[local.volume_keys[each.key]].id
  server_id = hcloud_server.nodes[each.key].id
  automount = false
}
resource "hcloud_load_balancer" "cluster" {
  depends_on         = [hcloud_managed_certificate.cluster]
  name               = var.deployment_name
  load_balancer_type = "lb11"
  location           = var.location
  labels             = local.labels
}
resource "hcloud_load_balancer_network" "cluster" {
  load_balancer_id = hcloud_load_balancer.cluster.id
  subnet_id        = hcloud_network_subnet.cluster.id
}
# Both HTTP and HTTPS terminate at the load balancer and reach all nodes over HTTP.
resource "hcloud_load_balancer_target" "nodes" {
  for_each         = local.nodes
  type             = "server"
  load_balancer_id = hcloud_load_balancer.cluster.id
  server_id        = hcloud_server.nodes[each.key].id
  use_private_ip   = true
  depends_on       = [hcloud_load_balancer_network.cluster]
}
resource "hcloud_load_balancer_service" "client" {
  count            = var.client_traffic_enabled ? 1 : 0
  load_balancer_id = hcloud_load_balancer.cluster.id
  protocol         = var.protocol
  listen_port      = var.protocol == "https" ? 443 : 80
  destination_port = 8080
  dynamic "http" {
    for_each = var.protocol == "https" ? [1] : []
    content {
      certificates  = [hcloud_managed_certificate.cluster[0].id]
      redirect_http = true
    }
  }
  health_check {
    protocol = "http"
    port     = 8080
    interval = 10
    timeout  = 5
    retries  = 3
    http {
      path         = "/health"
      status_codes = ["2??"]
      domain       = var.public_domain != "" ? var.public_domain : hcloud_load_balancer.cluster.ipv4
      tls          = false
    }
  }
}
moved {
  from = hcloud_load_balancer_service.client
  to   = hcloud_load_balancer_service.client[0]
}
resource "hcloud_managed_certificate" "cluster" {
  count        = var.protocol == "https" ? 1 : 0
  name         = "${var.deployment_name}-tls"
  domain_names = [var.public_domain]
  labels       = local.labels
  lifecycle {
    precondition {
      condition     = var.public_domain != ""
      error_message = "Hetzner-managed HTTPS requires a domain with Hetzner DNS or delegated ACME validation."
    }
  }
}
output "inventory" {
  value = {
    schema_version         = 2
    provider               = "hetzner"
    lifecycle_version      = 1
    client_traffic_enabled = var.client_traffic_enabled
    load_balancer_id       = hcloud_load_balancer.cluster.id
    network_id             = hcloud_network.cluster.id
    firewall_id            = hcloud_firewall.cluster.id
    endpoint               = "${var.protocol}://${var.public_domain != "" ? var.public_domain : hcloud_load_balancer.cluster.ipv4}"
    public_ip              = hcloud_load_balancer.cluster.ipv4
    https_mode             = var.protocol == "https" ? "load-balancer" : null
    nodes = { for key, node in local.nodes : key => {
      id         = node.id, shard = node.shard, replica = node.replica,
      host       = hcloud_server.nodes[key].ipv4_address, peer_host = node.ip,
      server_id  = hcloud_server.nodes[key].id
      volume_id  = hcloud_volume.wal[local.volume_keys[key]].id
      volume_key = local.volume_keys[key]
    } }
    volumes = { for key, volume in hcloud_volume.wal : key => {
      id = volume.id, name = volume.name, retained = !contains(values(local.volume_keys), key)
    } }
  }
}
