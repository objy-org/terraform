resource "random_id" "bucket" {
  byte_length = 6
}

resource "random_password" "cluster_secret" {
  length  = 48
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "random_password" "admin" {
  count   = var.admin_password == null ? 1 : 0
  length  = 24
  special = false
}

locals {
  node_port            = 8080
  prefix               = trim(var.s3_prefix, "/")
  bucket_name          = var.s3_bucket != null ? var.s3_bucket : "${var.deployment_name}-${random_id.bucket.hex}"
  s3_server            = trimsuffix(trimprefix(var.s3_endpoint, "https://"), "/")
  admin_password       = var.admin_password != null ? var.admin_password : random_password.admin[0].result
  network_has_capacity = can(cidrhost(var.network_cidr, 9 + var.shards * var.replicas))

  common_labels = merge(var.labels, {
    "objydb-deployment" = var.deployment_name
    "objydb-managed-by" = "terraform"
  })

  nodes = {
    for node in flatten([
      for shard in range(var.shards) : [
        for replica in range(var.replicas) : {
          key        = "s${shard + 1}-r${replica + 1}"
          id         = "${var.deployment_name}-s${shard + 1}-r${replica + 1}"
          shard      = "shard-${shard}"
          shard_no   = shard
          replica_no = replica
          index      = shard * var.replicas + replica
          private_ip = local.network_has_capacity ? cidrhost(var.network_cidr, 10 + shard * var.replicas + replica) : "0.0.0.0"
        }
      ]
    ]) : node.key => node
  }

  shard_map = {
    version = 1
    shards = {
      for shard in range(var.shards) : "shard-${shard}" => {
        peers = [
          for replica in range(var.replicas) : {
            url = "http://${local.network_has_capacity ? cidrhost(var.network_cidr, 10 + shard * var.replicas + replica) : "0.0.0.0"}:${local.node_port}"
          }
        ]
      }
    }
  }

  node_configs = {
    for key, node in local.nodes : key => {
      node = {
        id            = node.id
        url           = "http://${node.private_ip}:${local.node_port}"
        retainOps     = 256
        syncBatchSize = 4096
      }
      server = {
        port = local.node_port
        cors = false
      }
      storage = {
        engine = "object"
      }
      cluster = {
        syncMs               = 2500
        forwardTimeoutMs     = 60000
        replicationTimeoutMs = 60000
        secret               = { fromEnvironment = "OBJYDB_CLUSTER_SECRET" }
        hints = {
          enabled          = true
          debounceMs       = 25
          maxScopesPerHint = 128
        }
        shardMapStore = {
          mode   = "s3"
          prefix = local.prefix
          key    = "cluster/shard-map.json"
        }
      }
      auth = {
        jwtSecret              = { fromEnvironment = "OBJYDB_JWT_SECRET" }
        accessTokenTtlSeconds  = 3600
        refreshTokenTtlSeconds = 1209600
        users = [{
          _id      = "admin"
          username = "admin"
          password = { fromEnvironment = "OBJYDB_ADMIN_PASSWORD" }
          role     = "admin"
          admin    = true
        }]
      }
      files = {
        mode = "s3"
      }
      memoryGuard = {
        enabled             = true
        limitMb             = var.heap_mb
        rejectWritesPercent = 85
        resumeWritesPercent = 78
        checkMs             = 1000
      }
      persistence = {
        mode              = "s3"
        prefix            = local.prefix
        flushMs           = 5000
        opBatchSize       = 10000
        journalMaxBytes   = 4194304
        snapshotMs        = 60000
        segmentBytes      = 16777216
        compactJournals   = true
        snapshotDirtyOnly = true
        snapshotRetention = { keepLatest = 5 }
        restoreMode       = "scoped"
        ack               = "localWal"
        localWal = {
          mode    = "on"
          dir     = "/var/lib/objydb/wal"
          fsync   = true
          flushMs = 0
        }
        s3 = {
          bucket          = local.bucket_name
          endpoint        = var.s3_endpoint
          region          = var.s3_region
          accessKeyId     = { fromEnvironment = "OBJYDB_S3_ACCESS_KEY" }
          secretAccessKey = { fromEnvironment = "OBJYDB_S3_SECRET_KEY" }
          forcePathStyle  = true
        }
      }
    }
  }

  environment_file = join("\n", [
    "OBJYDB_CLUSTER_SECRET=${jsonencode(random_password.cluster_secret.result)}",
    "OBJYDB_JWT_SECRET=${jsonencode(random_password.jwt_secret.result)}",
    "OBJYDB_ADMIN_PASSWORD=${jsonencode(local.admin_password)}",
    "OBJYDB_S3_ACCESS_KEY=${jsonencode(var.s3_access_key)}",
    "OBJYDB_S3_SECRET_KEY=${jsonencode(var.s3_secret_key)}",
    "",
  ])
}

check "network_capacity" {
  assert {
    condition     = local.network_has_capacity
    error_message = "network_cidr does not have enough usable addresses for the requested shards and replicas."
  }
}
