include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "component" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_common/traefik.hcl"
  merge_strategy = "deep"
}

locals {
  region_dir = dirname(find_in_parent_folders("region.hcl"))
}

dependency "k3s" {
  config_path = "${local.region_dir}/k3s"

  mock_outputs = {
    kubernetes_api              = "https://127.0.0.1:6443"
    cluster_ca_certificate_data = ""
    client_certificate_data     = ""
    client_key_data             = ""
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  kubernetes_host             = dependency.k3s.outputs.kubernetes_api
  cluster_ca_certificate_data = dependency.k3s.outputs.cluster_ca_certificate_data
  client_certificate_data     = dependency.k3s.outputs.client_certificate_data
  client_key_data             = dependency.k3s.outputs.client_key_data
}
