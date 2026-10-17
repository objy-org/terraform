output "endpoint" {
  description = "Public OBJY DB endpoint."
  value       = "http://${hcloud_load_balancer.cluster.ipv4}:${var.load_balancer_port}"
}

output "topology" {
  description = "Installed fixed cluster topology."
  value = {
    shards     = var.shards
    replicas   = var.replicas
    node_count = length(local.nodes)
    nodes = {
      for key, node in local.nodes : key => {
        id         = node.id
        shard      = node.shard
        replica    = node.replica_no + 1
        private_ip = node.private_ip
      }
    }
  }
}

output "storage" {
  description = "Durable OBJY DB storage location."
  value = {
    endpoint = var.s3_endpoint
    region   = var.s3_region
    bucket   = local.bucket_name
    prefix   = local.prefix
  }
}

output "admin_username" {
  value = "admin"
}

output "admin_password" {
  description = "Initial global administrator password."
  value       = local.admin_password
  sensitive   = true
}

output "node_public_ips" {
  description = "Break-glass public addresses for the cluster nodes."
  value       = { for key, server in hcloud_server.nodes : key => server.ipv4_address }
}
