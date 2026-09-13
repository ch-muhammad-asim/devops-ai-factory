# cert-manager on K3s — Terragrunt managed

cert-manager is deployed from the official upstream chart through `infrastructure/modules/helm-release` and `infrastructure/live/dev/us-east-1/cert-manager`.

## Versions

| Component | Version |
|---|---:|
| K3s | `v1.36.4+k3s1` |
| HashiCorp Helm provider | `3.2.0` |
| cert-manager chart/application | `v1.21.1` |

The chart is managed directly; there is no wrapper `Chart.yaml` and no install/test/uninstall script.

## CRD policy

The values use the current chart model:

```yaml
crds:
  enabled: true
  keep: true
```

`keep: true` prevents Helm uninstall from deleting cert-manager CRDs and cascading deletion of certificate resources.

## Dependency/order

The Terragrunt unit depends on K3s for Kubernetes credentials and on Traefik for the repository's desired platform ordering.

```text
K3s -> Traefik -> cert-manager
```

## Plan/apply

```bash
cd infrastructure/live/dev/us-east-1/cert-manager
terragrunt plan
terragrunt apply
```

## ACME/DNS examples

The files under `examples/` are reference manifests only. They are intentionally **not** a second deployment path. If a ClusterIssuer, Certificate or DNS-01 integration is promoted into the managed platform, model it in Terraform/Kubernetes resources behind a Terragrunt unit rather than adding a manual `kubectl apply` runbook.

Never commit a real DNS provider API token.

## Runtime verification

Optional post-deployment checks:

```bash
kubectl -n cert-manager get pods
kubectl get crd | grep cert-manager.io
```
