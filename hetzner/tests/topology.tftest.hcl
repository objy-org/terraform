mock_provider "hcloud" {}
mock_provider "minio" {}
mock_provider "random" {
  mock_resource "random_id" {
    defaults = {
      hex = "a1b2c3d4e5f6"
    }
  }
  mock_resource "random_password" {
    defaults = {
      result = "test-secret-value"
    }
  }
}

run "single_node_topology" {
  command = plan

  variables {
    deployment_name = "objydb-test"
    shards          = 1
    replicas        = 1
    release_url     = "https://example.test/objydb.tar.gz"
    release_sha256  = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    s3_access_key   = "test-access"
    s3_secret_key   = "test-secret"
  }

  assert {
    condition     = output.topology.node_count == 1
    error_message = "A one-by-one topology must create one node."
  }

  assert {
    condition     = output.topology.nodes["s1-r1"].shard == "shard-0"
    error_message = "The first node must own shard-0."
  }

  assert {
    condition = can(yamldecode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
      node_id            = "objydb-test-s1-r1"
      heap_mb            = 4096
      wal_volume_id      = 12345
      release_url        = "https://example.test/objydb.tar.gz"
      release_sha256     = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      release_format     = var.release_format
      node_runtime       = var.node_runtime
      config_base64      = base64encode("{}")
      environment_base64 = base64encode("OBJYDB_TEST=secret")
    })))
    error_message = "Rendered cloud-init must be valid YAML."
  }
}

run "source_release_bootstrap" {
  command = plan

  variables {
    deployment_name = "objydb-source-test"
    release_format  = "github-source"
    release_url     = "https://example.test/source.tar.gz"
    release_sha256  = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    s3_access_key   = "test-access"
    s3_secret_key   = "test-secret"
  }

  assert {
    condition = anytrue([
      for file in yamldecode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
        node_id            = "objydb-source-test-s1-r1"
        heap_mb            = 2048
        wal_volume_id      = 12345
        release_url        = var.release_url
        release_sha256     = var.release_sha256
        release_format     = var.release_format
        node_runtime       = var.node_runtime
        config_base64      = base64encode("{}")
        environment_base64 = base64encode("OBJYDB_TEST=secret")
      })).write_files :
      try(
        file.path == "/etc/netplan/60-objydb-private.yaml" &&
        yamldecode(file.content).network.ethernets.enp7s0.dhcp4 &&
        yamldecode(file.content).network.ethernets.ens10.dhcp4 &&
        yamldecode(file.content).network.ethernets.enp7s0.optional &&
        yamldecode(file.content).network.ethernets.ens10.optional,
        false
      )
    ])
    error_message = "Both Hetzner private-interface names must have persistent DHCP configuration without blocking boot on the absent interface."
  }

  assert {
    condition = alltrue([
      for file in yamldecode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
        node_id            = "objydb-source-test-s1-r1"
        heap_mb            = 2048
        wal_volume_id      = 12345
        release_url        = var.release_url
        release_sha256     = var.release_sha256
        release_format     = var.release_format
        node_runtime       = var.node_runtime
        config_base64      = base64encode("{}")
        environment_base64 = base64encode("OBJYDB_TEST=secret")
      })).write_files :
      try(file.defer, false) if file.owner == "root:objydb"
    ])
    error_message = "Files owned by objydb must be deferred until cloud-init has created that group."
  }

  assert {
    condition = anytrue([
      for file in yamldecode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
        node_id            = "objydb-source-test-s1-r1"
        heap_mb            = 2048
        wal_volume_id      = 12345
        release_url        = var.release_url
        release_sha256     = var.release_sha256
        release_format     = var.release_format
        node_runtime       = var.node_runtime
        config_base64      = base64encode("{}")
        environment_base64 = base64encode("OBJYDB_TEST=secret")
      })).write_files :
      file.path == "/usr/local/sbin/objydb-install" &&
      strcontains(file.content, "set -euo pipefail") &&
      strcontains(file.content, "--strip-components=1") &&
      strcontains(file.content, "npm ci --omit=dev --ignore-scripts") &&
      strcontains(file.content, var.node_runtime.sha256)
    ])
    error_message = "Source bootstrap must verify archives, strip the source directory, install locked dependencies, and stop on failure."
  }

  assert {
    condition = strcontains(file("${path.module}/templates/cloud-init.yaml.tftpl"), "User=objydb") && strcontains(
      file("${path.module}/templates/cloud-init.yaml.tftpl"),
      "ExecStartPre=+/usr/local/sbin/objydb-mount-wal"
    )
    error_message = "Mounting the WAL requires root while the database process remains unprivileged."
  }
}

run "replicated_sharded_topology" {
  command = plan

  variables {
    deployment_name = "objydb-test"
    shards          = 3
    replicas        = 2
    release_url     = "https://example.test/objydb.tar.gz"
    release_sha256  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    s3_access_key   = "test-access"
    s3_secret_key   = "test-secret"
  }

  assert {
    condition     = output.topology.node_count == 6
    error_message = "A three-by-two topology must create six nodes."
  }

  assert {
    condition     = output.topology.nodes["s3-r2"].private_ip == "10.42.0.15"
    error_message = "Node addresses must be deterministic."
  }
}

run "rejects_undersized_network" {
  command = plan

  variables {
    deployment_name = "objydb-test"
    shards          = 4
    replicas        = 2
    network_cidr    = "10.42.0.0/29"
    release_url     = "https://example.test/objydb.tar.gz"
    release_sha256  = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    s3_access_key   = "test-access"
    s3_secret_key   = "test-secret"
  }

  expect_failures = [check.network_capacity]
}
