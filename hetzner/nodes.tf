resource "hcloud_volume" "wal" {
  for_each = local.nodes

  name     = "${each.value.id}-wal"
  size     = var.wal_volume_size_gb
  location = var.location
  format   = "ext4"
  labels = merge(local.common_labels, {
    "objydb-node"  = each.value.id
    "objydb-shard" = each.value.shard
  })
}

resource "hcloud_server" "nodes" {
  for_each = local.nodes

  name                     = each.value.id
  server_type              = var.server_type
  image                    = var.server_image
  location                 = var.location
  placement_group_id       = hcloud_placement_group.shards[tostring(each.value.shard_no)].id
  firewall_ids             = [hcloud_firewall.nodes.id]
  ssh_keys                 = var.ssh_public_key == null ? [] : [hcloud_ssh_key.admin[0].id]
  shutdown_before_deletion = true

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    subnet_id = hcloud_network_subnet.cluster.id
    ip        = each.value.private_ip
    alias_ips = []
  }

  labels = merge(local.common_labels, {
    "objydb-node"    = each.value.id
    "objydb-shard"   = each.value.shard
    "objydb-replica" = tostring(each.value.replica_no + 1)
  })

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    node_id            = each.value.id
    heap_mb            = var.heap_mb
    wal_volume_id      = hcloud_volume.wal[each.key].id
    release_url        = var.release_url
    release_sha256     = var.release_sha256
    config_base64      = base64encode(jsonencode(local.node_configs[each.key]))
    environment_base64 = base64encode(local.environment_file)
  })

  depends_on = [minio_s3_object.shard_map]
}

resource "hcloud_volume_attachment" "wal" {
  for_each = local.nodes

  volume_id = hcloud_volume.wal[each.key].id
  server_id = hcloud_server.nodes[each.key].id
  automount = false
}
