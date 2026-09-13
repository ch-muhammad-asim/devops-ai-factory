# Kubernetes add-on values managed by Terragrunt

This directory contains **values for official upstream Helm charts**. The charts themselves are managed as Terraform `helm_release` resources through Terragrunt.

There are no local wrapper charts and no install/uninstall shell scripts.

## Terragrunt units

| Add-on | Live unit | Upstream chart |
|---|---|---|
| Traefik | `infrastructure/live/dev/us-east-1/traefik` | `traefik/traefik` `41.4.0` |
| cert-manager | `infrastructure/live/dev/us-east-1/cert-manager` | `jetstack/cert-manager` `v1.21.1` |
| Argo CD | `infrastructure/live/dev/us-east-1/argocd` | `argo/argo-cd` `10.8.1` |

The dependency order is:

```text
K3s -> Traefik -> cert-manager -> Argo CD
```

Apply the whole region stack:

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all plan
terragrunt run --all apply
```

Apply only one release:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt plan
terragrunt apply
```

Chart pins/repositories are defined in `infrastructure/live/_common/*.hcl`; this directory only owns chart values and reference examples.

`kubectl` can be used after deployment for runtime troubleshooting, but it is not part of the deployment lifecycle.
