mock_provider "hcloud" {}

variables {
  deployment_name  = "odb-0123456789ab"
  location         = "fsn1"
  server_type      = "cx23"
  shards           = 2
  replicas         = 2
  protocol         = "http"
  ssh_public_key   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMR3hHsJfKO4JJOJ9V4E+9n/6tQwMCziBo/7SIt2rgl test"
  bootstrap_script = "#!/bin/bash\necho ready\n"
}

run "http_cluster" {
  command = plan
  assert {
    condition     = hcloud_load_balancer_service.client[0].protocol == "http" && hcloud_load_balancer_service.client[0].destination_port == 8080 && length(hcloud_managed_certificate.cluster) == 0
    error_message = "HTTP must forward directly to DB nodes without a certificate."
  }
  assert {
    condition     = length(output.inventory.nodes) == 4 && length(hcloud_load_balancer_target.nodes) == 4
    error_message = "Each replica needs a server and HTTP load-balancer target."
  }
  assert {
    condition     = output.inventory.nodes["s2-r2"].peer_host == "10.42.0.13"
    error_message = "Peer addresses must be deterministic."
  }
  assert {
    condition     = length(hcloud_volume.wal) == 4 && length(hcloud_placement_group.shards) == 2
    error_message = "Each node needs a WAL volume, and each shard a spread group."
  }
  assert {
    condition = can(yamldecode(templatefile("${path.module}/bootstrap.yaml.tftpl", {
      script_base64 = base64encode(var.bootstrap_script)
      volume_id     = 123
    })))
    error_message = "Cloud-init must be valid YAML."
  }
}

run "https_load_balancer" {
  command = plan
  variables {
    protocol      = "https"
    public_domain = "db.yourdomain.com"
  }
  assert {
    condition     = length(hcloud_load_balancer_target.nodes) == 4 && output.inventory.https_mode == "load-balancer"
    error_message = "The HTTPS load balancer must route to every DB node."
  }
  assert {
    condition     = hcloud_load_balancer_service.client[0].protocol == "https" && hcloud_load_balancer_service.client[0].listen_port == 443 && hcloud_load_balancer_service.client[0].destination_port == 8080
    error_message = "The load balancer must terminate TLS and forward HTTP to port 8080."
  }
  assert {
    condition     = length(hcloud_managed_certificate.cluster) == 1 && hcloud_managed_certificate.cluster[0].domain_names == toset(["db.yourdomain.com"]) && length(hcloud_load_balancer_service.client[0].http[0].certificates) == 1 && hcloud_load_balancer_service.client[0].http[0].redirect_http
    error_message = "Hetzner must own the certificate and redirect public HTTP to HTTPS."
  }
  assert {
    condition     = hcloud_load_balancer_service.client[0].health_check[0].protocol == "http" && hcloud_load_balancer_service.client[0].health_check[0].port == 8080 && !hcloud_load_balancer_service.client[0].health_check[0].http[0].tls
    error_message = "DB node health checks must use private HTTP."
  }
  assert {
    condition     = alltrue([for rule in hcloud_firewall.cluster.rule : !contains(["80", "443"], rule.port)])
    error_message = "DB nodes must not expose public HTTP or TLS ports."
  }
  assert {
    condition     = output.inventory.endpoint == "https://db.yourdomain.com" && hcloud_load_balancer_service.client[0].health_check[0].http[0].domain == "db.yourdomain.com"
    error_message = "The client endpoint must use the certificate's domain."
  }
}

run "https_requires_domain" {
  command = plan
  variables { protocol = "https" }
  expect_failures = [hcloud_managed_certificate.cluster[0]]
}

run "paused_cluster" {
  command = plan
  variables { client_traffic_enabled = false }
  assert {
    condition     = length(hcloud_load_balancer_service.client) == 0 && !output.inventory.client_traffic_enabled
    error_message = "Maintenance must remove the listener while retaining the load balancer and targets."
  }
  assert {
    condition     = output.inventory.schema_version == 2 && output.inventory.lifecycle_version == 1 && length(hcloud_load_balancer_target.nodes) == 4
    error_message = "Lifecycle inventory and targets must remain available during maintenance."
  }
}

run "replica_growth_keeps_addresses" {
  command = plan
  variables {
    replicas = 3
    node_addresses = {
      s1-r1 = "10.42.0.10", s1-r2 = "10.42.0.11", s2-r1 = "10.42.0.12", s2-r2 = "10.42.0.13",
      s1-r3 = "10.42.0.14", s2-r3 = "10.42.0.15"
    }
  }
  assert {
    condition     = output.inventory.nodes["s2-r1"].peer_host == "10.42.0.12" && output.inventory.nodes["s1-r3"].peer_host == "10.42.0.14"
    error_message = "Adding replicas must not renumber retained peers."
  }
}

run "shrink_retains_wal" {
  command = plan
  variables {
    shards                 = 1
    replicas               = 1
    client_traffic_enabled = false
    wal_volumes = {
      s1-r1 = { name = "odb-0123456789ab-s1-r1-wal" }, s1-r2 = { name = "odb-0123456789ab-s1-r2-wal" },
      s2-r1 = { name = "odb-0123456789ab-s2-r1-wal" }, s2-r2 = { name = "odb-0123456789ab-s2-r2-wal" }
    }
  }
  assert {
    condition     = length(hcloud_server.nodes) == 1 && length(hcloud_volume.wal) == 4 && output.inventory.volumes["s2-r1"].retained
    error_message = "Shrinking must retain WAL disks even after retiring their nodes."
  }
}

run "regrow_uses_fresh_wal" {
  command = plan
  variables {
    shards   = 1
    replicas = 1
    wal_volumes = {
      s1-r1    = { name = "odb-0123456789ab-s1-r1-wal" }
      s1-r1-v2 = { name = "odb-0123456789ab-s1-r1-v2-wal" }
    }
    node_volume_keys = { s1-r1 = "s1-r1-v2" }
  }
  assert {
    condition     = output.inventory.nodes["s1-r1"].volume_key == "s1-r1-v2" && output.inventory.volumes["s1-r1"].retained && !output.inventory.volumes["s1-r1-v2"].retained
    error_message = "A reused node slot must attach a new disk while keeping its retired WAL."
  }
}
