# Argo CD on K3s — Terragrunt managed

Argo CD is deployed from the official `argo-cd` chart through `infrastructure/modules/helm-release` and `infrastructure/live/dev/us-east-1/argocd`.

## Versions

| Component | Version |
|---|---:|
| K3s | `v1.36.4+k3s1` |
| HashiCorp Helm provider | `3.2.0` |
| Argo CD Helm chart | `10.8.1` |
| Argo CD application | `v3.5.2` |

The old local wrapper chart and install/uninstall scripts were removed.

## Baseline access model

The Argo CD server uses `ClusterIP`, and public ingress is disabled by default. `server.insecure=true` means the service speaks HTTP inside the cluster so Traefik can terminate TLS when an ingress is intentionally enabled.

## Dependency/order

```text
K3s -> Traefik -> cert-manager -> Argo CD
```

## Plan/apply

```bash
cd infrastructure/live/dev/us-east-1/argocd
terragrunt plan
terragrunt apply
```

## Optional Traefik ingress

`values-traefik.example.yaml` is a reference override. To make ingress part of managed state, customize the hostname/TLS settings and intentionally merge those values into the Argo CD values consumed by `_common/argocd.hcl`; then use `terragrunt plan/apply`. Do not run a separate Helm command.

For Internet-facing access, use cert-manager/TLS rather than leaving the example's HTTP-only setting unchanged.

## Runtime verification

Optional checks after retrieving kubeconfig from the K3s Terragrunt output:

```bash
kubectl -n argocd get pods
kubectl -n argocd get deployments,statefulsets,services
```
