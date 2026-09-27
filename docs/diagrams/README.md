# Architecture diagrams

This directory contains rendered architecture assets used by the repository documentation.

## K3s platform overview

![K3s on AWS platform architecture](k3s-platform-overview.svg)

The SVG represents the current repository profile:

- Terragrunt drives Terraform for AWS infrastructure and S3 remote state.
- VPC, EC2 and K3s are separate lifecycle/state boundaries.
- EC2 uses Canonical Ubuntu Server 26.04 LTS, resolved from Canonical's public AWS SSM AMI parameter.
- K3s is installed during EC2 first boot through cloud-init/user data.
- AWS Systems Manager is used for secure kubeconfig retrieval without SSH.
- the current `dev/us-east-1` profile is five nodes: three K3s servers with embedded etcd, tainted `CriticalAddonsOnly`, and two K3s agents for workloads.
- K3s bundled Traefik is disabled.
- Traefik, cert-manager and Argo CD are official Helm charts managed as Terraform `helm_release` resources through separate Terragrunt units.
- the control plane tolerates one server failure, but the operator API endpoint is anchored to server-1's Elastic IP, so client access is not yet HA.
- the `k3s-platform-overview.svg` diagram predates the five-node profile and still shows a single node.

The SVG is committed as a repository asset so GitHub and downstream documentation render the same reviewed architecture image.

The simpler non-technical AI Factory visual lives at [`../ai-factory/architecture.svg`](../ai-factory/architecture.svg).
