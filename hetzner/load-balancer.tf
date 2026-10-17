resource "hcloud_load_balancer" "cluster" {
  name               = "${var.deployment_name}-lb"
  load_balancer_type = var.load_balancer_type
  location           = var.location
  labels             = local.common_labels

  algorithm {
    type = "round_robin"
  }
}

resource "hcloud_load_balancer_network" "cluster" {
  load_balancer_id        = hcloud_load_balancer.cluster.id
  subnet_id               = hcloud_network_subnet.cluster.id
  enable_public_interface = true
}

resource "hcloud_load_balancer_target" "nodes" {
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.cluster.id
  label_selector   = "objydb-deployment=${var.deployment_name}"
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.cluster, hcloud_server.nodes]
}

resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.cluster.id
  protocol         = "http"
  listen_port      = var.load_balancer_port
  destination_port = local.node_port

  http {
    sticky_sessions = false
  }

  health_check {
    protocol = "http"
    port     = local.node_port
    interval = 10
    timeout  = 5
    retries  = 3

    http {
      path         = "/health"
      status_codes = ["2??"]
    }
  }
}
