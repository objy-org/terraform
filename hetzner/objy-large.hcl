# OBJY DB release v0.1.0.
# Large: 12 nodes, 4 shard(s), 3 copies, 8 GiB heap, 40 GB WAL per node.
# From hetzner/: terraform plan -var-file=objy-large.hcl -out=objydb.tfplan
# Supply HCLOUD_TOKEN, TF_VAR_s3_access_key and TF_VAR_s3_secret_key.
# Initial deployments only; changing presets is not a resizing workflow.

deployment_name = "objydb-objy-large"
location        = "fsn1"
server_type     = "cx43" # x86: matches the pinned Linux x64 Node.js runtime below.
server_image    = "ubuntu-24.04"

# Choose the topology before the first apply.
# Changing shards or replicas later is not an automated migration.
shards             = 4
replicas           = 3
heap_mb            = 8192
wal_volume_size_gb = 40
network_cidr       = "10.42.0.0/24"

# Bootstrap from the tagged source archive and verify its exact bytes.
release_format = "github-source"
release_url    = "https://codeload.github.com/objy-org/objy/tar.gz/refs/tags/v0.1.0"
release_sha256 = "4c1b7cc82eae150fcb31b923ffcf1084aaf70ad46d17fef7d91a7ffe8efb430e"

node_runtime = {
  url    = "https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-x64.tar.gz"
  sha256 = "1084aa36196bba4c3a5e69a1ee388a6e4ff729dad09445fbcd434b28fe3c24af"
}

s3_endpoint = "https://fsn1.your-objectstorage.com"
s3_region   = "fsn1"
s3_bucket   = null # Creates a private bucket; set an existing bucket name to reuse one.
s3_prefix   = "objy-release-large"

load_balancer_type = "lb11"
load_balancer_port = 80 # The module exposes HTTP; use this trial with test data.

# Generate the initial admin password; read it with terraform output -raw admin_password.
admin_password = null

# Optional SSH access: replace null with your public key and [] with your IP/32.
ssh_public_key    = null
ssh_allowed_cidrs = []

labels = {
  environment = "test"
  release     = "objy"
  preset      = "large"
}

# The existing module protects its bucket and shard-map object from destruction.
# A plain terraform destroy will therefore not remove the entire deployment.
