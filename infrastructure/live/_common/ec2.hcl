# Shared EC2 compute defaults.
# The node bootstrap is delivered as user data, so compute converges on first
# boot with no Run Command association, SSH access, or operator-side scripting.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//ec2"
}

locals {
  env_config    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_config = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  k3s_config    = read_terragrunt_config("${get_repo_root()}/infrastructure/live/_common/k3s.hcl")

  cluster_name = "${local.env_config.locals.project_name}-${local.env_config.locals.environment}-${local.region_config.locals.aws_region}"
}

inputs = {
  instance_type        = "t3.medium"
  root_volume_size     = 30
  primary_instance_key = "primary"

  # Canonical's public SSM parameter always resolves the latest published
  # Ubuntu Server 26.04 LTS AMD64 gp3 AMI in the active AWS region.
  ami_ssm_parameter_name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"

  # Deletion protection. Clear these and apply once before any run that has to
  # replace or destroy the node, including an OS/AMI or bootstrap change.
  enable_termination_protection = true
  enable_stop_protection        = true

  # EC2 nodes are map-driven and created with Terraform for_each. The current
  # repository profile intentionally has one primary node; add map entries here
  # or in an environment override when additional compute nodes are required.
  instances = {
    primary = {}
  }

  user_data = templatefile(
    "${get_repo_root()}/infrastructure/templates/k3s-install.sh.tftpl",
    {
      cluster_name = local.cluster_name
      k3s_version  = local.k3s_config.locals.k3s_version
      traefik_flag = local.k3s_config.locals.enable_traefik ? "" : "--disable traefik"
    },
  )
}
