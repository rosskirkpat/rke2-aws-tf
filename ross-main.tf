provider "aws" {
    region                  = var.aws_region
    shared_credentials_file = var.aws_credentials_file
    profile                 = var.aws_profile
}

locals {
    cluster_name           = "${var.prefix}-rke2-rancher"
    aws_region             = var.aws_region
    rancher_version        = "v2.6.3"
    cert_manager_version   = "v1.5.1"
    rke2_version           = "v1.21.7+rke2r1"
    num_clusters           = 10
    vpc_security_group_ids = module.servers.security_group

    tags = {
        "terraform" = "true",
        "env"       = "cloud-enabled",
        "Owner"       = var.owner,
        "DoNotDelete" = "true",
    }
    rke2_downstream = {
        servers = 3,
        agents = 2
    }
}

# Key Pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_pem" {
  filename        = "${local.cluster_name}.pem"
  content         = tls_private_key.ssh.private_key_pem
  file_permission = "0600"
}

resource "random_password" "rancher_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

#
# Network
#
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "ross-rke2-${local.cluster_name}"
  cidr = "10.88.0.0/16"

  azs             = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]
  public_subnets  = ["10.88.1.0/24", "10.88.2.0/24", "10.88.3.0/24"]
  private_subnets = ["10.88.101.0/24", "10.88.102.0/24", "10.88.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_vpn_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Add in required tags for proper AWS CCM integration
  public_subnet_tags = merge({
    "kubernetes.io/cluster/${module.rke2.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                            = "1"
  }, local.tags)

  private_subnet_tags = merge({
    "kubernetes.io/cluster/${module.rke2.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                   = "1"
  }, local.tags)

  tags = merge({
    "kubernetes.io/cluster/${module.rke2.cluster_name}" = "shared"
  }, local.tags)
}

#
# Server
#
module "rke2" {
  source = "./modules/rke2"

  cluster_name = local.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnets      = module.vpc.public_subnets # Note: Public subnets used for demo purposes, this is not recommended in production

#   ami                   = data.aws_ami.rhel8.image_id # Note: Multi OS is primarily for example purposes
  ami                   = module.ami.ubuntu-20_04
  ssh_authorized_keys   = [tls_private_key.ssh.public_key_openssh]
  instance_type         = "t3a.medium"
  controlplane_internal = false # Note this defaults to best practice of true, but is explicitly set to public for demo purposes
  servers               = 3

  # Enable AWS Cloud Controller Manager
  enable_ccm = true

  rke2_config = <<-EOT
node-label:
  - "name=server"
  - "os=ubuntu"
EOT

  tags = local.tags
}

#
# Generic agent pool
#
module "agents" {
  source = "./modules/agent-nodepool"

  name    = "agent"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets # Note: Public subnets used for demo purposes, this is not recommended in production

#   ami                 = data.aws_ami.rhel8.image_id # Note: Multi OS is primarily for example purposes
  ami                 = module.ami.ubuntu-20_04
  ssh_authorized_keys = [tls_private_key.ssh.public_key_openssh]
  spot                = false
  asg                 = { min : 1, max : 10, desired : 2 }
  instance_type       = "t3a.large"

  # Enable AWS Cloud Controller Manager and Cluster Autoscaler
  enable_ccm        = true
  enable_autoscaler = true

  rke2_config = <<-EOT
node-label:
  - "name=agent"
  - "os=ubuntu"
EOT

  cluster_data = module.rke2.cluster_data

  tags = local.tags
}

# For demonstration only, lock down ssh access in production
# resource "aws_security_group_rule" "quickstart_ssh" {
#   from_port         = 22
#   to_port           = 22
#   protocol          = "tcp"
#   security_group_id = module.rke2.cluster_data.cluster_sg
#   type              = "ingress"
#   cidr_blocks       = ["0.0.0.0/0"]
# }

# Generic outputs as examples
output "rke2" {
  value = module.rke2
}

# Example method of fetching kubeconfig from state store, requires aws cli and bash locally
resource "null_resource" "kubeconfig" {
  depends_on = [module.rke2]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "aws s3 cp ${module.rke2.kubeconfig_path} rke2.yaml"
  }
}

data "local_file" "kubeconfig" {
    filename = "${path.module}/rke2.yaml"
}

module "rancher" {
    depends_on = [module.rke2]
    source = "./modules/rancher"
    hostname = module.elb.dns
    cert_manager_version = local.cert_manager_version
    kubeconfig = local_file.kubeconfig
    rancher_version = local.rancher_version
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "aws_key" {
#   for_each = local.num_clusters
#   key_name   = "tf-downstream-${var.rancher_cluster_name}-${each.key}"
  key_name   = "rke2-downstream-awskey" 
  public_key = tls_private_key.ssh_key.public_key_openssh
}

module "scale" {
  depends_on = [
    module.rke2,
    module.rancher
  ]
  for_each            = local.num_clusters
  source              = "./modules/scale-test"
  vpc_id              = module.vpc.vpc_id
  subnets             = module.vpc.public_subnets # Note: Public subnets used for demo purposes, this is not recommended in production
  ami                 = module.ami.ubuntu-20_04
  ssh_authorized_keys = [tls_private_key.ssh_key.public_key_openssh]
  key_name            = aws_key_pair.aws_key.key_name
  instance_type       = "t3a.medium"
  agent_count         = local.rke2_downstream.servers
  server_count        = local.rke2_downstream.agents
  agent_name          = "${var.prefix}-rke2-agent_cluster${each.key}"
  server_name         = "${var.prefix}-rke2-server_cluster${each.key}"
  tags                = local.tags
  vpc_security_group_ids = module.servers.security_group
}
