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
      config_base64      = base64encode("{}")
      environment_base64 = base64encode("OBJYDB_TEST=secret")
    })))
    error_message = "Rendered cloud-init must be valid YAML."
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
