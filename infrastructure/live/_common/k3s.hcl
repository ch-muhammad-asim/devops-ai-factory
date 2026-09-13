# Shared K3s configuration defaults.
# K3s is installed by EC2 user data during first boot. This unit retrieves the
# resulting kubeconfig and feeds the downstream Helm units.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//k3s"
}

locals {
  # Exact release pin for reproducible rebuilds. The compute layer renders the
  # node bootstrap from these same values.
  k3s_version = "v1.36.4+k3s1"

  # Traefik is managed separately by the pinned Helm deployment.
  enable_traefik = false
}

inputs = {
  k3s_version = local.k3s_version

  # Fail the run rather than hang if the node never publishes a kubeconfig.
  kubeconfig_timeout_seconds = 900
}
