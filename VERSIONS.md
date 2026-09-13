# Version matrix

Runtime/platform versions are intentionally pinned so a rebuild does not silently change behavior.

| Component | Version / constraint | Source of truth |
|---|---|---|
| Ubuntu Server | `26.04 LTS` (Resolute Raccoon), latest Canonical AMD64 gp3 AMI for the region | `infrastructure/live/_common/ec2.hcl` |
| K3s | `v1.36.4+k3s1` | `infrastructure/live/_common/k3s.hcl` |
| HashiCorp Helm provider | `3.2.0` | `infrastructure/modules/helm-release/versions.tf` |
| Traefik Helm chart | `41.4.0` | `infrastructure/live/_common/traefik.hcl` |
| Traefik Proxy | `v3.7.12` | upstream chart `41.4.0` |
| Traefik whoami example image | `v1.12.0` | `kubernetes/helm/traefik/examples/whoami.yaml` |
| cert-manager Helm chart/application | `v1.21.1` | `infrastructure/live/_common/cert-manager.hcl` |
| Argo CD Helm chart | `10.8.1` | `infrastructure/live/_common/argocd.hcl` |
| Argo CD application | `v3.5.2` | upstream chart `10.8.1` |
| Terraform CLI | `>= 1.10.0` (S3 native locking) | `infrastructure/modules/*/versions.tf` |
| AWS provider | `>= 5.0, < 7.0` | `infrastructure/modules/*/versions.tf` |

## Ubuntu AMI resolution

The EC2 layer resolves Canonical's current Ubuntu Server 26.04 LTS image through the AWS public SSM parameter instead of hard-coding an AMI ID:

```text
/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id
```

This keeps the operating-system release fixed at Ubuntu 26.04 LTS while allowing Canonical security/maintenance AMI refreshes to be picked up intentionally when a plan is applied. An AMI change replaces an EC2 node, so always review the EC2 plan first.

Canonical's Ubuntu-on-AWS documentation describes the same public SSM hierarchy:
<https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/>

## Ownership

- Operators invoke **Terragrunt only** for infrastructure and platform lifecycle.
- EC2 lifecycle, Ubuntu AMI selection, IAM/SSM access, EIP, security groups and EBS are owned by `infrastructure/modules/ec2` plus the shared inputs in `infrastructure/live/_common/ec2.hcl`.
- K3s is installed during first boot by `infrastructure/templates/k3s-install.sh.tftpl` delivered as EC2 user data.
- The `k3s` Terraform unit retrieves the generated kubeconfig over AWS Systems Manager and exposes it to downstream Helm units.
- Traefik, cert-manager and Argo CD are Terraform `helm_release` resources driven through Terragrunt leaf units.
- Helm chart versions live in `infrastructure/live/_common/{traefik,cert-manager,argocd}.hcl`.
- `kubernetes/helm/*/values.yaml` contains upstream chart values; local wrapper charts are intentionally not used.

## Existing Amazon Linux nodes

Changing an already-created node from Amazon Linux 2023 to Ubuntu 26.04 LTS is an **EC2 replacement**, not an in-place OS upgrade. Because this repository enables EC2 termination/stop protection, first clear protection on the existing node and apply that change before applying the Ubuntu replacement.

From the EC2 unit:

```bash
cd infrastructure/live/dev/us-east-1/ec2
terragrunt apply \
  -var='enable_termination_protection=false' \
  -var='enable_stop_protection=false'
```

Then return to the region directory, review the replacement plan, and apply:

```bash
cd ..
terragrunt run --all plan
terragrunt run --all apply
```

The replacement node is created from Ubuntu 26.04 LTS and the committed configuration re-enables the protection flags on the new node.

## Verify state through Terragrunt

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all output
```

Retrieve the kubeconfig path through the K3s unit if `kubectl` verification is needed:

```bash
cd k3s
terragrunt output kubeconfig_path
```

Then, optionally:

```bash
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
kubectl -n traefik get pods,svc
kubectl -n cert-manager get pods
kubectl -n argocd get pods
```
