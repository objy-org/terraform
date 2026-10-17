resource "hcloud_network" "cluster" {
  name     = "${var.deployment_name}-network"
  ip_range = var.network_cidr
  labels   = local.common_labels
}

resource "hcloud_network_subnet" "cluster" {
  network_id   = hcloud_network.cluster.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.network_cidr
}

resource "hcloud_firewall" "nodes" {
  name   = "${var.deployment_name}-nodes"
  labels = local.common_labels

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = tostring(local.node_port)
    source_ips  = [var.network_cidr]
    description = "OBJY DB peer and load-balancer traffic"
  }

  dynamic "rule" {
    for_each = var.ssh_public_key != null && length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = var.ssh_allowed_cidrs
      description = "Break-glass SSH access"
    }
  }

  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = [var.network_cidr]
    description = "Private-network diagnostics"
  }
}

resource "hcloud_ssh_key" "admin" {
  count = var.ssh_public_key == null ? 0 : 1

  name       = "${var.deployment_name}-admin"
  public_key = var.ssh_public_key
  labels     = local.common_labels
}

resource "hcloud_placement_group" "shards" {
  for_each = toset([for shard in range(var.shards) : tostring(shard)])

  name   = "${var.deployment_name}-shard-${each.key}"
  type   = "spread"
  labels = merge(local.common_labels, { "objydb-shard" = "shard-${each.key}" })
}
