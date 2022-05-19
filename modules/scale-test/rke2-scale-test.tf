locals {
  command_types = {
    secure_linux     = rancher2_cluster_v2.cluster.cluster_registration_token.0.node_command
    secure_windows   = rancher2_cluster_v2.cluster.cluster_registration_token.0.windows_node_command
    insecure_linux   = rancher2_cluster_v2.cluster.cluster_registration_token.0.insecure_node_command
    insecure_windows = rancher2_cluster_v2.cluster.cluster_registration_token.0.insecure_windows_node_command
  }
}

variable "num_clusters" {
    type = number
}

resource "rancher2_cluster_v2" "cluster" {
  count = var.num_clusters
  name = "rke2-downstream-${count.index}"

  provider = rancher2.admin
  fleet_namespace = "fleet-default"
  kubernetes_version = var.rke2_version
  tags = {    
      Name = "RKE2 downstream cluster #${count.index}"  
  }
}

resource "local_file" "downstream_kubeconfigs" {
  for_each = rancher2_cluster_v2.cluster
  filename = format("%s/%s", path.root, "${each.value.name}.yml")
  content = each.value.kube_config
}

# resource "null_resource" "server_command" {
#   for_each rancher2_cluster_v2.cluster
#   inputs = {
#     server_command = each.key.cluster_registration_token.0.node_command
#   }
      # dynamic "origin" {
      #   for_each = origin_group.value.origins
      #   content {
      #     hostname = origin.value.hostname
      #   }
#   for k, v in rancher2_cluster_v2.cluster : k => v.cluster_registration_token.0.node_command
# }

# resource "null_resource" "secure_command" {
#   dynamic "rke2" {
#     for_each rancher2_cluster_v2.cluster
#     content {
#       command = rke2.cluster_registration_token.0.node_command
#     }
#   }
# }

variable "join_command" {
  type = map(object)
  description = "The node command from Rancher to join a new or existing rke2 cluster"
}


resource "aws_instance" "rke2_server" {
  count = var.server_count
  tags = {
    Name        = "${var.prefix}-rke2-server_cluster"
    RKE2Cluster = "cluster${count.index}"  
  }

  key_name                    = var.key_name
  ami                         = var.ami
  instance_type		            = var.instance_type
  subnet_id                   = var.subnets
  vpc_security_group_ids      = var.vpc_security_group_ids
  source_dest_check           = "false"
  # user_data                   = base64encode(templatefile("files/user-data-linux.yml", { cluster_registration = format("%s%s","${rancher2_cluster_v2.rke2_win_cluster.cluster_registration_token[0].insecure_node_command}"," --etcd --controlplane") }))
  # user_data                   = base64encode(templatefile("files/user-data-linux.yml", { cluster_registration = format("%s%s",module.rancherv2.insecure_rke2_cluster_command," --etcd --controlplane") }))
  dynamic "rke2" {
    for_each = rancher2_cluster_v2.cluster
    content {
      command = rke2.cluster_registration_token.0.node_command
    }
  }
  user_data                   = base64encode(templatefile("files/cloud_config.yaml", { cluster_registration = format("%s%s",command," --etcd --controlplane") }))
 
  root_block_device {
    volume_size = var.instances.linux_master.volume_size
  }

  credit_specification {
    cpu_credits = "standard"
  }
}

resource "aws_instance" "rke2_agent" {
  count                       = var.agent_count
  tags = merge({
    Name        = "${var.prefix}-rke2-agent"
    }, var.tags)
  key_name                    = var.key_name
  ami                         = var.ami
  instance_type		            = var.instance_type
  subnet_id                   = var.subnets
  vpc_security_group_ids      = var.vpc_security_group_ids
  source_dest_check           = "false"
  # user_data                   = base64encode(templatefile("files/user-data-linux.yml", { cluster_registration = format("%s%s","${rancher2_cluster_v2.rke2_win_cluster.cluster_registration_token[0].insecure_node_command}"," --worker") }))
  dynamic "rke2" {
    for_each = rancher2_cluster_v2.cluster
    content {
      command = rke2.cluster_registration_token.0.node_command
    }
  }
  user_data                   = base64encode(templatefile("files/cloud_config.yaml", { cluster_registration = format("%s%s",command," --worker") }))
  # user_data                   = base64encode(templatefile("files/user-data-linux.yml", { cluster_registration = format("%s%s",module.rancher2.insecure_rke2_cluster_command," --worker") }))


  root_block_device {
    volume_size = var.instances.linux_worker.volume_size
  }

  credit_specification {
    cpu_credits = "standard"
  }
}
