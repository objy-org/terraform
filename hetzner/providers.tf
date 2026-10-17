provider "hcloud" {}

provider "minio" {
  minio_server   = local.s3_server
  minio_user     = var.s3_access_key
  minio_password = var.s3_secret_key
  minio_region   = var.s3_region
  minio_ssl      = true
}
