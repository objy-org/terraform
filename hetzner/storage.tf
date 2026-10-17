resource "minio_s3_bucket" "data" {
  count = var.s3_bucket == null ? 1 : 0

  bucket         = local.bucket_name
  acl            = "private"
  object_locking = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "minio_s3_object" "shard_map" {
  depends_on = [minio_s3_bucket.data]

  bucket_name  = local.bucket_name
  object_name  = "${local.prefix}/cluster/shard-map.json"
  content      = jsonencode(local.shard_map)
  content_type = "application/json"

  lifecycle {
    prevent_destroy = true
  }
}
