# ObjyDB Control Center infrastructure contract v2

This module handles cluster creation and installer-coordinated lifecycle operations for ObjyDB Control Center. It is separate
from the standalone `../../hetzner` module and does not change its existing state.

Terraform owns machines, persistent WAL volumes, networking, placement and the
public endpoint. Control Center owns object storage provisioning, the initial
shard map, database configuration and starting the runtime. No application
secrets are passed to Terraform. Provider authentication uses `HCLOUD_TOKEN`.

Control Center selects a suitable x86 server type, generates a dedicated SSH key,
and provides the OS bootstrap script. `inventory` is the only required output;
its schema version is 2, with `lifecycle_version = 1`. HTTP and HTTPS balance over every healthy node. For
HTTPS, `public_domain` is required and must support Hetzner-managed certificate
validation through Hetzner DNS or delegated ACME validation.

Terraform creates `hcloud_managed_certificate.cluster` and attaches it to the
load balancer's native HTTPS service. TLS terminates on the load balancer,
which redirects public HTTP to HTTPS and forwards private HTTP to node port
8080. Health checks also use private HTTP. The DB-node firewall does not expose
ports 80 or 443. Certificate issuance and renewal are owned by Hetzner, with no
certificate private keys or renewal services on DB nodes. Billable volumes,
servers and the load balancer depend on successful certificate creation.

`public_ip` is returned for the domain's A record, and HTTPS inventories set
`https_mode = "load-balancer"`. Users must point an A record at `public_ip` and
remove any AAAA record for the selected name. HTTP uses the public IP directly.

Lifecycle inputs are managed by the separate installer:

- `client_traffic_enabled = false` removes only the client service, including its HTTPS redirect. The load balancer, public address, certificate, network and targets remain allocated. The listener is restored only after private runtime verification.
- `node_addresses` persists assignments so changing replica count cannot renumber retained nodes.
- `wal_volumes` is the full retained disk registry, including retired slots. `node_volume_keys` maps active slots to their disks. Regrowing a retired slot gets a new key/disk. `prevent_destroy` remains enabled.
- Inventory includes server, volume, network, firewall and load-balancer IDs, the traffic flag, and retained volumes.

Initial creation uses the defaults. Setup retries still reject updates/deletes.
Resize is not a plain `terraform apply`: the installer must pause ingress, stop
and verify every old runtime/WAL, apply the reviewed capacity change, stage the
configuration, update the shard map, restore and verify before reopening.
Never change these variables in a live installation outside that coordinator.

The moved block migrates `hcloud_load_balancer_service.client` to `client[0]`.
Existing v1 snapshots require a reviewed, no-resource-mutation management upgrade;
they do not silently start using this source. Terraform state and module
snapshots stay in each installation's private directory. The canonical workspace
is recorded in `infrastructure.json` and may move beneath `plans/` after an
upgrade. Retain that directory and do not apply the superseded workspace.

Mocked tests cover HTTP/HTTPS, pause, address stability and volume retention.
Disposable live-cloud lifecycle qualification remains outstanding. The standalone
`../../hetzner` module is not adopted or changed by this workflow.
