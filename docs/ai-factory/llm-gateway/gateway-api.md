# Gateway API setup for the LLM Gateway

> **Research review:** 2026-09-13. This guide is for the repository's AI Factory profile on RKE2 / Kubernetes 1.36.x and applies unchanged to the current K3s `v1.36.4+k3s1` (Kubernetes 1.36) repository cluster, whose committed Traefik and cert-manager state it references. It documents the current Traefik + cert-manager Gateway API path and how it relates to LiteLLM.

## Important decision

**Kubernetes Gateway API is not a hard prerequisite for LiteLLM itself.**

LiteLLM can run perfectly well behind the existing Kubernetes `Ingress` path:

```text
client
  |
Traefik Ingress
  |
LiteLLM Service
  |
vLLM / KServe / KubeRay
```

Gateway API becomes a prerequisite only when this project deliberately chooses the **Gateway API exposure path** or later adopts the **Gateway API Inference Extension** for inference-aware routing.

The modern path is:

```text
client
  |
Gateway API
  |
Traefik Gateway controller
  |
HTTPRoute
  |
LiteLLM Service
  |
vLLM / KServe / KubeRay
```

For the first LiteLLM deployment, Gateway API is optional. For the longer-term AI Factory architecture it is worth enabling because it gives a standard routing API and provides the foundation required by the Gateway API Inference Extension.

---

## Current repository state

At the time of this review, the repository is **not yet Gateway API-enabled**.

Current Traefik configuration:

```yaml
providers:
  kubernetesGateway:
    enabled: false

gateway:
  enabled: false

gatewayClass:
  enabled: false
```

The repository currently pins:

```text
Traefik Helm chart: 41.4.0
Traefik Proxy:      v3.7.12
```

The current cert-manager configuration also does not enable Gateway API reconciliation.

Therefore do not assume Gateway API is already available just because Traefik and cert-manager are installed.

---

## Current upstream compatibility baseline

For a new Gateway API rollout, use the latest compatible versions rather than blindly choosing the numerically newest CRD bundle.

As of this review:

```text
Kubernetes:              1.36.x
Traefik Helm chart:      41.5.0
Traefik Proxy:           v3.7.13
Traefik documented
Gateway API support:     Standard v1.6.1
cert-manager:            v1.21.1 in this repository
```

The Gateway API project has released `v1.6.2`, but Traefik v3.7's current documentation explicitly states support for the Standard `v1.6.1` API. For this production profile, pin the version the selected Traefik release documents as supported:

```text
Gateway API CRDs: v1.6.1
```

Upgrade that pin only after the Traefik release notes/documentation validate the newer Gateway API bundle.

---

## Installation order

Use this order:

```text
1. Kubernetes 1.36 (RKE2 profile or current K3s cluster)
        |
2. Gateway API CRDs
        |
3. Traefik with kubernetesGateway enabled
        |
4. cert-manager with Gateway API support enabled
        |
5. Gateway / GatewayClass
        |
6. LiteLLM Helm release
        |
7. HTTPRoute -> LiteLLM Service
```

The CRDs must exist before Traefik starts its Gateway API provider. cert-manager should also see the CRDs at startup; if they were installed afterward, restart cert-manager.

---

## 1. Pre-flight checks

```bash
kubectl version
helm version
kubectl get nodes -o wide
kubectl get pods -A
```

Verify the current Traefik and cert-manager releases:

```bash
helm list -A | grep -E 'traefik|cert-manager'
```

Check whether Gateway API CRDs already exist:

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io || true
kubectl get crd gateways.gateway.networking.k8s.io || true
kubectl get crd httproutes.gateway.networking.k8s.io || true
```

---

## 2. Install Gateway API CRDs

The official Traefik chart **does not ship Gateway API CRDs anymore**. They must be installed separately.

For the currently documented Traefik v3.7 compatibility level:

```bash
export GATEWAY_API_VERSION=v1.6.1

kubectl apply --server-side=true \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
```

Verify:

```bash
kubectl get crd | grep gateway.networking.k8s.io
kubectl api-resources | grep -E 'GatewayClass|Gateway|HTTPRoute|GRPCRoute'
```

The `v1.6.1` standard-channel bundle installs these CRDs:

```text
GatewayClass
Gateway
ListenerSet
HTTPRoute
GRPCRoute
TCPRoute
TLSRoute
UDPRoute
ReferenceGrant
BackendTLSPolicy
```

### Why this is not installed with the Traefik Helm chart

The Traefik Helm chart no longer owns the Kubernetes Gateway API CRDs. This is deliberate: Gateway API is a Kubernetes SIG project and its CRDs have their own lifecycle.

Therefore the correct production model is:

```text
Gateway API CRDs
  -> installed/pinned separately

Traefik Helm chart
  -> installs the controller/RBAC/GatewayClass/Gateway integration
```

Do not hide the Gateway API CRD lifecycle inside the LiteLLM Helm release.

---

## 3. Upgrade/install Traefik through Helm with Gateway API enabled

The latest stable Traefik chart at this review is:

```bash
export TRAEFIK_CHART_VERSION=41.5.0
```

Add/update the chart repository:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

Inspect the exact chart before changing production:

```bash
helm show chart traefik/traefik \
  --version "${TRAEFIK_CHART_VERSION}"

helm show values traefik/traefik \
  --version "${TRAEFIK_CHART_VERSION}" \
  > /tmp/traefik-values-${TRAEFIK_CHART_VERSION}.yaml
```

Create a Gateway API override file:

```yaml
# /tmp/traefik-gateway-values.yaml
providers:
  kubernetesCRD:
    enabled: true
  kubernetesIngress:
    enabled: true
  kubernetesGateway:
    enabled: true

gatewayClass:
  enabled: true
  name: traefik

gateway:
  enabled: true
  name: traefik
  listeners:
    web:
      port: 8000
      protocol: HTTP
      namespacePolicy:
        from: All
```

This keeps the current Ingress/IngressRoute paths working while adding Gateway API support.

Render before upgrading:

```bash
helm template traefik traefik/traefik \
  --version "${TRAEFIK_CHART_VERSION}" \
  --namespace traefik \
  -f /tmp/traefik-gateway-values.yaml \
  > /tmp/traefik-gateway-rendered.yaml
```

Upgrade/install:

```bash
helm upgrade --install traefik traefik/traefik \
  --version "${TRAEFIK_CHART_VERSION}" \
  --namespace traefik \
  --create-namespace \
  -f /tmp/traefik-gateway-values.yaml \
  --wait \
  --timeout 10m
```

Verify:

```bash
kubectl -n traefik get pods
kubectl get gatewayclass
kubectl -n traefik get gateway
```

The Traefik Helm chart manages the Gateway API RBAC when `providers.kubernetesGateway.enabled=true`.

---

## 4. Repository/Terragrunt equivalent for Traefik

This repository does not run `helm upgrade` manually for platform components. Traefik is managed by Terraform `helm_release` through Terragrunt.

When adopting Gateway API here, update:

```text
infrastructure/live/_common/traefik.hcl
kubernetes/helm/traefik/values.yaml
```

The intended version pin becomes:

```hcl
chart_version = "41.5.0"
```

And the Traefik values should include:

```yaml
providers:
  kubernetesCRD:
    enabled: true
    allowCrossNamespace: false
    allowExternalNameServices: false
  kubernetesIngress:
    enabled: true
    allowExternalNameServices: false
    publishedService:
      enabled: true
  kubernetesGateway:
    enabled: true

gatewayClass:
  enabled: true
  name: traefik

gateway:
  enabled: true
  name: traefik
  listeners:
    web:
      port: 8000
      protocol: HTTP
      namespacePolicy:
        from: All
```

Then use the repository's normal operator workflow:

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all plan
terragrunt run --all apply
```

Do not manually `helm upgrade` a release that Terraform/Terragrunt owns; that creates configuration drift.

---

## 5. Enable cert-manager Gateway API support

The repository currently uses cert-manager `v1.21.1`.

Gateway API support is not enabled just by installing cert-manager. With current cert-manager, enable it through Helm configuration:

```yaml
config:
  gatewayAPI:
    enabled: true
```

For a direct Helm-managed cluster the command is conceptually:

```bash
helm upgrade --install cert-manager \
  oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.1 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set config.gatewayAPI.enabled=true
```

For this repository, update:

```text
kubernetes/helm/cert-manager/values.yaml
```

from:

```yaml
crds:
  enabled: true
  keep: true
```

to include:

```yaml
crds:
  enabled: true
  keep: true

config:
  gatewayAPI:
    enabled: true
```

Then deploy through Terragrunt rather than running Helm manually.

If Gateway API CRDs were installed **after** cert-manager was already running, restart cert-manager after enabling the integration:

```bash
kubectl rollout restart deployment cert-manager -n cert-manager
kubectl rollout status deployment cert-manager -n cert-manager
```

Verify:

```bash
kubectl -n cert-manager get pods
kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

---

## 6. Add HTTPS to the Traefik Gateway

For TLS managed by cert-manager, configure an HTTPS listener and annotate the Gateway.

Example values:

```yaml
gateway:
  enabled: true
  name: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  listeners:
    web:
      port: 8000
      protocol: HTTP
      namespacePolicy:
        from: All
    websecure:
      port: 8443
      protocol: HTTPS
      hostname: llm.example.com
      namespacePolicy:
        from: All
      certificateRefs:
        - name: llm-gateway-tls
          kind: Secret
          group: ""
```

Important: the TLS Secret referenced by a Gateway listener is normally in the same namespace as the Gateway unless a cross-namespace reference is explicitly authorized. In the layout above the Gateway lives in `traefik`, so `llm-gateway-tls` is created in the `traefik` namespace.

Verify certificate creation:

```bash
kubectl -n traefik get certificate
kubectl -n traefik get secret llm-gateway-tls
kubectl -n traefik describe gateway traefik
```

---

## 7. Install LiteLLM with Helm

Gateway API does not install LiteLLM. LiteLLM remains its own Helm release.

Use the pinned LiteLLM chart documented in the parent `README.md`:

```bash
export LITELLM_CHART_VERSION=1.100.1
```

Install it as a private ClusterIP service and disable its traditional Ingress when the Gateway API path is being used:

```yaml
# /tmp/litellm-values.yaml
service:
  type: ClusterIP
  port: 4000

ingress:
  enabled: false
```

The rest of the production values still include the LiteLLM master key, PostgreSQL, model backends, resources, PDB, migration job and optional Redis as described in the parent guide.

Install:

```bash
helm upgrade --install litellm \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${LITELLM_CHART_VERSION}" \
  --namespace llm-gateway \
  --create-namespace \
  -f /tmp/litellm-values.yaml \
  --wait \
  --timeout 15m
```

Verify:

```bash
kubectl -n llm-gateway get pods
kubectl -n llm-gateway get svc
```

---

## 8. Create an HTTPRoute for LiteLLM

With LiteLLM exposed only as a ClusterIP Service, create an `HTTPRoute`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: litellm
  namespace: llm-gateway
spec:
  parentRefs:
    - name: traefik
      namespace: traefik
  hostnames:
    - llm.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: litellm
          port: 4000
```

Apply:

```bash
kubectl apply -f httproute-litellm.yaml
```

Verify acceptance:

```bash
kubectl -n llm-gateway get httproute
kubectl -n llm-gateway describe httproute litellm
```

Look for `Accepted=True` and `ResolvedRefs=True` conditions.

If the LiteLLM Service name differs, discover it first:

```bash
kubectl -n llm-gateway get svc
```

---

## 9. Validate the complete request path

Check the Gateway:

```bash
kubectl get gatewayclass
kubectl -n traefik get gateway
kubectl -n traefik describe gateway traefik
```

Check the route:

```bash
kubectl -n llm-gateway get httproute
kubectl -n llm-gateway describe httproute litellm
```

Check LiteLLM:

```bash
kubectl -n llm-gateway get pods,svc
kubectl -n llm-gateway logs deploy/litellm --tail=100
```

Then test:

```bash
curl -sS https://llm.example.com/health/readiness
```

And an authenticated inference request:

```bash
curl -sS https://llm.example.com/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local-llm",
    "messages": [
      {"role": "user", "content": "Hello from Gateway API"}
    ]
  }'
```

The traffic path is:

```text
client
  |
DNS / TLS
  |
Gateway
  |
Traefik Kubernetes Gateway provider
  |
HTTPRoute
  |
LiteLLM ClusterIP Service
  |
LiteLLM Pod
  |
vLLM / KServe / KubeRay
  |
GPU worker
```

---

## 10. Do we need the Gateway API Inference Extension too?

No, not for the first LLM Gateway deployment.

Gateway API and Gateway API Inference Extension are separate layers:

```text
Gateway API
  -> standard Kubernetes north-south/service routing API

Gateway API Inference Extension
  -> adds inference-specific APIs such as InferencePool
  -> allows inference-aware endpoint selection for model-server replicas
```

The first production milestone can be:

```text
Gateway API
  |
LiteLLM
  |
one vLLM Service
```

Add the Inference Extension only when one logical model has multiple GPU-backed replicas and normal Service load balancing is no longer sufficient.

Future path:

```text
client
  |
Traefik / Gateway API
  |
LiteLLM
  |
Inference-aware Gateway / InferencePool
  |
+----------+----------+----------+
|          |          |          |
vLLM 1    vLLM 2    vLLM 3     ...
GPU        GPU        GPU
```

The Inference Extension also has its own CRDs/controller implementation lifecycle. Do not install it merely because Gateway API is enabled.

---

## 11. Rollback

If Gateway API causes problems, the existing Ingress path can remain enabled while the new route is tested.

Because the recommended Traefik values keep both providers enabled:

```yaml
providers:
  kubernetesIngress:
    enabled: true
  kubernetesGateway:
    enabled: true
```

migration can be gradual.

Rollback steps:

```bash
kubectl -n llm-gateway delete httproute litellm
```

Then restore LiteLLM `ingress.enabled=true` and use the existing Traefik Ingress path.

Do not remove Gateway API CRDs while any Gateway API resources still exist.

---

## 12. Security rules

- Terminate TLS on the Gateway.
- Keep LiteLLM authentication enabled even when the route is internal.
- Do not expose vLLM directly to normal clients.
- Use `ClusterIP` for LiteLLM and inference backends unless there is a specific reason not to.
- Restrict cross-namespace routes deliberately; `from: All` is convenient but broad. For a hardened multi-tenant cluster, use namespace selectors or same-namespace ownership.
- Use NetworkPolicy to restrict LiteLLM egress to inference backends, PostgreSQL, Redis and explicitly allowed external providers.
- Keep Traefik dashboard private.
- Pin the Traefik chart, Gateway API CRDs, cert-manager and LiteLLM versions.
- Review CRD/controller compatibility before upgrades.

---

## Recommended decision for this repository

Do **not** make Gateway API a blocker for proving the first LiteLLM + vLLM inference flow.

Use this progression:

```text
Milestone 1
Traefik Ingress -> LiteLLM -> vLLM

Milestone 2
Install Gateway API CRDs
Enable Traefik kubernetesGateway
Enable cert-manager Gateway API support
Create Gateway + HTTPRoute

Milestone 3
Gateway API -> LiteLLM -> vLLM

Milestone 4
Add Gateway API Inference Extension only if multi-replica GPU routing needs it
```

This keeps the initial AI Factory simple while moving the platform toward the Kubernetes-native Gateway API model without unnecessarily coupling LiteLLM installation to the inference-routing extension.

## Official references

- Kubernetes Gateway API: <https://gateway-api.sigs.k8s.io/>
- Gateway API releases: <https://github.com/kubernetes-sigs/gateway-api/releases>
- Traefik Kubernetes Gateway provider: <https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/>
- Traefik Helm chart: <https://github.com/traefik/traefik-helm-chart>
- cert-manager Gateway API: <https://cert-manager.io/docs/usage/gateway/>
- LiteLLM Helm package: <https://github.com/BerriAI/litellm/pkgs/container/litellm-helm>
- Gateway API Inference Extension: <https://gateway-api-inference-extension.sigs.k8s.io/>
