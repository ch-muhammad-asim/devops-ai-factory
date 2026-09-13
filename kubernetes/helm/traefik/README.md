# Traefik on K3s — Terragrunt managed

Traefik is deployed from the official upstream chart through `infrastructure/modules/helm-release` and the live Terragrunt unit `infrastructure/live/dev/us-east-1/traefik`.

## Versions

| Component | Version |
|---|---:|
| K3s | `v1.36.4+k3s1` |
| HashiCorp Helm provider | `3.2.0` |
| Traefik Helm chart | `41.4.0` |
| Traefik Proxy | `v3.7.12` |
| whoami reference image | `v1.12.0` |

`values.yaml` is written for the **upstream Traefik chart directly**. The historical wrapper chart and install/test/uninstall scripts were removed.

## Resource baseline

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 512Mi

env:
  - name: GOMAXPROCS
    value: "2"
```

The CPU request remains `100m` for scheduling while the CPU limit is intentionally absent so Traefik can burst. The key is omitted rather than set to `null`, which the chart renders as a zero limit that the API server rejects. Memory is capped at `512Mi`. Validate the ceiling under representative traffic before scaling this baseline to larger workloads.

## Plan/apply

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt plan
terragrunt apply
```

Or operate the complete stack from the region directory:

```bash
cd ..
terragrunt run --all apply
```

## Service exposure

K3s ServiceLB remains enabled. Traefik uses a `LoadBalancer` Service, allowing ports 80/443 to be exposed on the node in the current single-node profile.

The dashboard is disabled by default.

## Optional HTTPS redirect

`values-https-redirect.example.yaml` is a reference override. If the redirect becomes part of the desired platform state, merge it into `values.yaml` (or intentionally combine the files in `_common/traefik.hcl`) and apply the Traefik Terragrunt unit. Do not perform a separate manual Helm upgrade.

## Runtime verification

After retrieving kubeconfig with `terragrunt output -raw kubeconfig` from the K3s unit, optional checks include:

```bash
kubectl -n traefik get pods,svc
kubectl get ingressclass traefik
```
