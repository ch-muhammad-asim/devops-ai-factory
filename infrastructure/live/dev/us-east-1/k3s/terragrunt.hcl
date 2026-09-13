include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "component" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_common/k3s.hcl"
  merge_strategy = "deep"
}

locals {
  region_dir = dirname(find_in_parent_folders("region.hcl"))
}

dependency "ec2" {
  config_path = "${local.region_dir}/ec2"

  mock_outputs = {
    instance_id = "i-00000000000000000"
    public_ip   = "203.0.113.10"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  cluster_name = include.root.locals.cluster_name
  instance_id  = dependency.ec2.outputs.instance_id
  public_ip    = dependency.ec2.outputs.public_ip
}
