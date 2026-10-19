# OBJY DB 0.0.1-alpha, tag objy, commit eb221e0826dce0359c16558389abafd155006505.
# Use with this updated Hetzner module (github-source support is required).
# From this directory: terraform plan -var-file=objy-release.hcl -out=objydb.tfplan
# Then review the plan and run: terraform apply objydb.tfplan
# Supply HCLOUD_TOKEN, TF_VAR_s3_access_key, and TF_VAR_s3_secret_key in the environment.
# Run terraform init first if this module has not been initialized.
#
# Docker alternative (run from /Users/marco/Documents/GitHub/objydb-terraform/hetzner):
# tf() {
#   docker run --rm -i -v "$PWD:/workspace" -w /workspace \
#     -e HCLOUD_TOKEN -e TF_VAR_s3_access_key -e TF_VAR_s3_secret_key \
#     hashicorp/terraform:1.13.5 "$@"
# }
# tf init
# tf plan -var-file=objy-release.hcl -out=objydb.tfplan
# tf apply objydb.tfplan
# tf output endpoint
# tf output -raw admin_password

deployment_name = "objydb-objy-test"
location        = "fsn1"
server_type     = "cx23" # x86: matches the pinned Linux x64 Node.js runtime below.
server_image    = "ubuntu-24.04"

# Small trial deployment. Choose the topology before the first apply.
# Changing shards or replicas later is not an automated migration.
shards             = 1
replicas           = 1
heap_mb            = 2048
wal_volume_size_gb = 10
network_cidr       = "10.42.0.0/24"

# The GitHub release has source archives only. Pin its commit and exact bytes.
release_format = "github-source"
release_url    = "https://codeload.github.com/spoo-technologies/objy-db/tar.gz/eb221e0826dce0359c16558389abafd155006505"
release_sha256 = "60b426e1e3bc8c210bd37d8cae08c4bc4195ab274d58a08d94cd59326fca2fa5"

node_runtime = {
  url    = "https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-x64.tar.gz"
  sha256 = "1084aa36196bba4c3a5e69a1ee388a6e4ff729dad09445fbcd434b28fe3c24af"
}

s3_endpoint = "https://fsn1.your-objectstorage.com"
s3_region   = "fsn1"
s3_bucket   = null # Creates a private bucket; set an existing bucket name to reuse one.
s3_prefix   = "objy-release-test"

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
}

# The existing module protects its bucket and shard-map object from destruction.
# A plain terraform destroy will therefore not remove the entire trial deployment.
