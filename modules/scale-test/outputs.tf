output "rke2_cluster_names" {
  value = {
    for k, v in rancher2_cluster_v2.cluster : k => v.name
  }
  depends_on = [local_file.downstream_kubeconfigs]
}

output "secure_rke2_cluster_command" {
  value = {
    for k, v in rancher2_cluster_v2.cluster : k => v.cluster_registration_token.0.node_command
  }
  depends_on = [local_file.downstream_kubeconfigs]
}

output "insecure_rke2_cluster_command" {
  value = {
    for k, v in rancher2_cluster_v2.cluster : k => v.cluster_registration_token.0.insecure_node_command
  }
  depends_on = [local_file.downstream_kubeconfigs]
}

output "secure_rke2_cluster_windows_command" {
  value = {
    for k, v in rancher2_cluster_v2.cluster : k => v.cluster_registration_token.0.windows_node_command
  }
  depends_on = [local_file.downstream_kubeconfigs]
}

output "insecure_rke2_cluster_windows_command" {
  value = {
    for k, v in rancher2_cluster_v2.cluster : k => v.cluster_registration_token.0.insecure_windows_node_command
  }
  depends_on = [local_file.downstream_kubeconfigs]
}