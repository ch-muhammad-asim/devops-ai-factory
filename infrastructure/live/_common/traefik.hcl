# Traefik is managed as a Terraform helm_release, driven by Terragrunt.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//helm-release"
}

inputs = {
  release_name    = "traefik"
  namespace       = "traefik"
  repository      = "https://traefik.github.io/charts"
  chart           = "traefik"
  chart_version   = "41.4.0"
  values_yaml     = file("${get_repo_root()}/kubernetes/helm/traefik/values.yaml")
  timeout_seconds = 600
}
