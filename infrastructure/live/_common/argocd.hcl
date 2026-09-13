# Argo CD is managed as a Terraform helm_release, driven by Terragrunt.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//helm-release"
}

inputs = {
  release_name    = "argocd"
  namespace       = "argocd"
  repository      = "https://argoproj.github.io/argo-helm"
  chart           = "argo-cd"
  chart_version   = "10.8.1"
  values_yaml     = file("${get_repo_root()}/kubernetes/helm/argocd/values.yaml")
  timeout_seconds = 600
}
