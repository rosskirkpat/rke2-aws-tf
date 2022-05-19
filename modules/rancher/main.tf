variable "cert_manager_version" {
    type = string
}
variable "rancher_version" {
    type = string
}
variable "cluster_name" {
    type = string
}
variable "hostname" {
    type = string
}

variable "owner" {
    type = string
}

resource "random_password" "rancher_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}


# Helm resources

# Install cert-manager helm chart
resource "helm_release" "cert_manager" {
  repository       = "https://charts.jetstack.io"
  name             = "cert-manager"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# Install Rancher helm chart
resource "helm_release" "rancher_server" {
  depends_on = [
    helm_release.cert_manager
  ]
  repository       = "https://releases.rancher.com/server-charts/stable"
  name             = "rancher"
  chart            = "rancher"
  version          = var.rancher_version
  namespace        = "cattle-system"
  create_namespace = true
  wait             = true

  set {
    name  = "hostname"
    value = var.hostname
  }

  set {
    name  = "replicas"
    value = "3"
  }

  set {
    name  = "bootstrapPassword"
    value = "admin" # TODO: change this once the terraform provider has been updated with the new pw bootstrap logic
  }
}

provider "rancher2" {
  alias     = "bootstrap"
  insecure  = true
  api_url   = var.hostname
  bootstrap = true
  timeout   = "300s"
}

# Create a new rancher2_bootstrap using bootstrap provider config
resource "rancher2_bootstrap" "admin" {

  provider   = rancher2.bootstrap
  initial_password = "admin"
  password   = random_password.rancher_password.result
  telemetry  = false
}

# Provider config for admin
provider "rancher2" {
  alias     = "admin"
  api_url   = rancher2_bootstrap.admin.url
  token_key = rancher2_bootstrap.admin.token
  insecure  = true
}

resource "rancher2_setting" "server-url" {
  provider = rancher2.admin
  name     = "server-url"
  value    = rancher2_bootstrap.admin.url
}

resource "rancher2_token" "rancher-token" {
  provider    = rancher2.admin
  description = "Terraform ${var.owner} local cluster token"
}

# data "rancher2_cluster" "local" {
#   name = "local"
#   depends_on = [
#     rancher2_bootstrap.admin
#   ]
# }

# Create a new rancher2 resource using admin provider config
resource "rancher2_catalog" "rancher" {
  provider = rancher2.admin
  name     = "rancher"
  version  = "helm_v3"
  url      = "https://releases.rancher.com/server-charts/stable"
}

#
# Rancher backup
#
resource "rancher2_app_v2" "rancher-backup" {
  provider   = rancher2.admin
  cluster_id = "local"
  name       = "rancher-backup"
  namespace  = "cattle-resources-system"
  repo_name  = "rancher-charts"
  chart_name = "rancher-backup"
}

data "rancher2_role_template" "admin" {
  depends_on = [rancher2_catalog.rancher]
  provider   = rancher2.admin
  name       = "Cluster Owner"
}