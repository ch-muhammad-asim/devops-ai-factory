locals {
  env_config    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_config = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment  = local.env_config.locals.environment
  project_name = local.env_config.locals.project_name
  aws_region   = local.region_config.locals.aws_region
  account_id   = get_aws_account_id()

  # Region-aware names allow the same environment to exist in multiple regions
  # without colliding on account-global resources such as IAM roles.
  cluster_name = "${local.project_name}-${local.environment}-${local.aws_region}"

  repo_root   = get_repo_root()
  modules_dir = "${local.repo_root}/infrastructure/modules"

  state_bucket = get_env(
    "TG_STATE_BUCKET",
    "${local.project_name}-terraform-state-${local.account_id}-${local.aws_region}",
  )

  common_tags = {
    Environment = local.environment
    Project     = local.project_name
    Cluster     = local.cluster_name
    Region      = local.aws_region
    ManagedBy   = "terragrunt"
    Terraform   = "true"
  }
}

remote_state {
  backend = "s3"

  config = {
    bucket = local.state_bucket

    # Keep state identity independent from the repository folder depth. This
    # also preserves the original backend keys during the repository refactor.
    key          = "env/${local.environment}/region/${local.aws_region}/${basename(path_relative_to_include())}/terraform.tfstate"
    region       = local.aws_region
    encrypt      = true
    use_lockfile = true

    s3_bucket_tags = local.common_tags
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF_PROVIDER
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = {
          Environment = "${local.environment}"
          Project     = "${local.project_name}"
          Cluster     = "${local.cluster_name}"
          Region      = "${local.aws_region}"
          ManagedBy   = "terragrunt"
          Terraform   = "true"
        }
      }
    }
  EOF_PROVIDER
}

inputs = {
  environment = local.environment
  region      = local.aws_region
  tags        = local.common_tags
}
