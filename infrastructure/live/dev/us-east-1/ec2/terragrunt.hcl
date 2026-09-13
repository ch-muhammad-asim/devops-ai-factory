include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "component" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_common/ec2.hcl"
  merge_strategy = "deep"
}

locals {
  region_dir = dirname(find_in_parent_folders("region.hcl"))

  operator_cidr = get_env(
    "TG_OPERATOR_CIDR",
    "${trimspace(run_cmd("--terragrunt-quiet", "curl", "-fsS", "https://checkip.amazonaws.com"))}/32",
  )
}

dependency "vpc" {
  config_path = "${local.region_dir}/vpc"

  mock_outputs = {
    vpc_id            = "vpc-00000000000000000"
    public_subnet_ids = ["subnet-00000000000000000"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  name      = "${include.root.locals.cluster_name}-node"
  vpc_id    = dependency.vpc.outputs.vpc_id
  subnet_id = dependency.vpc.outputs.public_subnet_ids[0]

  ingress_rules = {
    http = {
      description = "HTTP ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }

    https = {
      description = "HTTPS ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }

    kubernetes_api = {
      description = "Kubernetes API"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_ipv4   = local.operator_cidr
    }
  }
}
