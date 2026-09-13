# Terragrunt-managed Helm release module

This Terraform module is consumed only through Terragrunt. It configures the HashiCorp Helm provider from K3s client credentials produced by the `k3s` unit and manages one upstream Helm release declaratively.

The operator does not run `helm install`, wrapper shell scripts, or a Makefile. Lifecycle is `terragrunt plan`, `terragrunt apply`, and `terragrunt destroy` from the corresponding live unit.

The Helm provider is pinned in `versions.tf`; chart versions are pinned by the component `_common/*.hcl` files.
