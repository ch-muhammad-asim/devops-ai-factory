output "release_name" {
  description = "Managed Helm release name."
  value       = helm_release.this.name
}

output "namespace" {
  description = "Kubernetes namespace containing the release."
  value       = helm_release.this.namespace
}

output "status" {
  description = "Helm release status reported by the provider."
  value       = helm_release.this.status
}

output "chart_version" {
  description = "Pinned chart version."
  value       = var.chart_version
}
