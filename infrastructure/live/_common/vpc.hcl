# Shared VPC component defaults.
# Environment/region leaf units include this file and override only what differs.
terraform {
  source = "${get_repo_root()}/infrastructure/modules//vpc"
}

inputs = {
  vpc_cidr            = "10.20.0.0/16"
  public_subnet_cidrs = ["10.20.1.0/24"]
}
