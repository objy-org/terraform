variable "deployment_name" {
  description = "Stable lowercase name used for all deployment resources."
  type        = string
  default     = "objydb"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.deployment_name))
    error_message = "deployment_name must contain 2-32 lowercase letters, numbers, or hyphens."
  }
}

variable "location" {
  description = "Hetzner Cloud location for servers, volumes, and the load balancer."
  type        = string
  default     = "fsn1"
}

variable "server_type" {
  description = "Hetzner Cloud server type used by every OBJY DB node."
  type        = string
  default     = "ccx33"
}

variable "server_image" {
  description = "Base operating-system image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "shards" {
  description = "Number of object shards. Fixed after the initial deployment in V1."
  type        = number
  default     = 1

  validation {
    condition     = floor(var.shards) == var.shards && var.shards >= 1 && var.shards <= 64
    error_message = "shards must be an integer between 1 and 64."
  }
}

variable "replicas" {
  description = "Number of replicas per shard."
  type        = number
  default     = 1

  validation {
    condition     = floor(var.replicas) == var.replicas && var.replicas >= 1 && var.replicas <= 10
    error_message = "replicas must be an integer between 1 and 10."
  }
}

variable "heap_mb" {
  description = "Maximum V8 heap size for each OBJY DB process."
  type        = number
  default     = 4096

  validation {
    condition     = floor(var.heap_mb) == var.heap_mb && var.heap_mb >= 512
    error_message = "heap_mb must be an integer of at least 512."
  }
}

variable "wal_volume_size_gb" {
  description = "Persistent WAL volume size for each node."
  type        = number
  default     = 10

  validation {
    condition     = floor(var.wal_volume_size_gb) == var.wal_volume_size_gb && var.wal_volume_size_gb >= 10
    error_message = "wal_volume_size_gb must be an integer of at least 10."
  }
}

variable "network_cidr" {
  description = "Private subnet used by OBJY DB peers and the load balancer."
  type        = string
  default     = "10.42.0.0/24"

  validation {
    condition     = can(cidrhost(var.network_cidr, 1))
    error_message = "network_cidr must be a valid CIDR."
  }
}

variable "ssh_public_key" {
  description = "Optional break-glass SSH public key."
  type        = string
  default     = null
  nullable    = true
}

variable "ssh_allowed_cidrs" {
  description = "Networks allowed to use SSH when ssh_public_key is configured."
  type        = list(string)
  default     = []
}

variable "release_url" {
  description = "HTTPS URL of the immutable OBJY DB Linux release archive."
  type        = string

  validation {
    condition     = startswith(var.release_url, "https://")
    error_message = "release_url must use HTTPS."
  }
}

variable "release_sha256" {
  description = "Lowercase SHA-256 checksum of the OBJY DB release archive."
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.release_sha256))
    error_message = "release_sha256 must be a lowercase 64-character SHA-256 checksum."
  }
}

variable "s3_endpoint" {
  description = "Hetzner Object Storage endpoint."
  type        = string
  default     = "https://fsn1.your-objectstorage.com"

  validation {
    condition     = startswith(var.s3_endpoint, "https://")
    error_message = "s3_endpoint must use HTTPS."
  }
}

variable "s3_region" {
  description = "Hetzner Object Storage location."
  type        = string
  default     = "fsn1"
}

variable "s3_access_key" {
  description = "Hetzner Object Storage access key."
  type        = string
  sensitive   = true
}

variable "s3_secret_key" {
  description = "Hetzner Object Storage secret key."
  type        = string
  sensitive   = true
}

variable "s3_bucket" {
  description = "Existing bucket name. A private bucket is generated when omitted."
  type        = string
  default     = null
  nullable    = true
}

variable "s3_prefix" {
  description = "OBJY DB namespace inside the bucket."
  type        = string
  default     = "data"

  validation {
    condition     = length(trim(var.s3_prefix, "/")) > 0
    error_message = "s3_prefix must be non-empty."
  }
}

variable "load_balancer_type" {
  description = "Hetzner load-balancer type."
  type        = string
  default     = "lb11"
}

variable "load_balancer_port" {
  description = "Public HTTP port exposed by the load balancer."
  type        = number
  default     = 80

  validation {
    condition     = floor(var.load_balancer_port) == var.load_balancer_port && var.load_balancer_port >= 1 && var.load_balancer_port <= 65535
    error_message = "load_balancer_port must be a valid TCP port."
  }
}

variable "admin_password" {
  description = "Optional initial global administrator password. A password is generated when omitted."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "labels" {
  description = "Additional labels added to supported Hetzner resources."
  type        = map(string)
  default     = {}
}
