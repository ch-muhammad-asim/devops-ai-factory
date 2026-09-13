locals {
  kubeconfig         = yamldecode(data.local_file.kubeconfig.content)
  kubeconfig_cluster = local.kubeconfig.clusters[0].cluster
  kubeconfig_user    = local.kubeconfig.users[0].user
}

output "k3s_version" {
  description = "Exact K3s version installed on the node."
  value       = var.k3s_version
}

output "kubeconfig_path" {
  description = "Local path holding the cluster kubeconfig. Use it with `kubectl --kubeconfig`, or export it as KUBECONFIG."
  value       = local.kubeconfig_path
}

output "kubernetes_api" {
  description = "Kubernetes API endpoint. Only the client credentials below are sensitive."
  value       = local.kubeconfig_cluster.server
}

output "cluster_ca_certificate_data" {
  description = "Base64-encoded Kubernetes cluster CA used by downstream Terragrunt Helm units."
  value       = local.kubeconfig_cluster["certificate-authority-data"]
  sensitive   = true
}

output "client_certificate_data" {
  description = "Base64-encoded Kubernetes client certificate used by downstream Terragrunt Helm units."
  value       = local.kubeconfig_user["client-certificate-data"]
  sensitive   = true
}

output "client_key_data" {
  description = "Base64-encoded Kubernetes client key used by downstream Terragrunt Helm units."
  value       = local.kubeconfig_user["client-key-data"]
  sensitive   = true
}

output "kubeconfig" {
  description = "Complete kubeconfig. Retrieve with `terragrunt output -raw kubeconfig`."
  value       = data.local_file.kubeconfig.content
  sensitive   = true
}
