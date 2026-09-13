# cert-manager is managed as a Terraform helm_release, driven by Terragrunt.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//helm-release"
}

inputs = {
  release_name    = "cert-manager"
  namespace       = "cert-manager"
  repository      = "https://charts.jetstack.io"
  chart           = "cert-manager"
  chart_version   = "v1.21.1"
  values_yaml     = file("${get_repo_root()}/kubernetes/helm/cert-manager/values.yaml")
  timeout_seconds = 600
}
