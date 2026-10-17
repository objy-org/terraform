terraform {
  required_version = ">= 1.7.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.44"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
