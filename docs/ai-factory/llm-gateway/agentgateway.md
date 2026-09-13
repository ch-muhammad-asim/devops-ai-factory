# AgentGateway on Kubernetes for the AI Factory

> **Research review:** 2026-09-13. This guide covers the Kubernetes-native **AgentGateway** project (`agentgateway/agentgateway`) for the repository's RKE2 / Kubernetes 1.36.x AI Factory direction. It applies equally to the current K3s `v1.36.4+k3s1` (Kubernetes 1.36) repository cluster, which is inside AgentGateway's 1.32-1.37 support range.
>
> **Important correction:** this is a different architecture from the Traefik + LiteLLM path documented in [`gateway-api.md`](gateway-api.md). AgentGateway is itself a Kubernetes Gateway API implementation for agentic, LLM, MCP and AI traffic. You do **not** need to enable Traefik's Gateway API provider just to use AgentGateway.

## Decision

If this project chooses **AgentGateway** as its AI/agent gateway, then **Kubernetes Gateway API CRDs are a prerequisite**.

The correct installation order is:

```text
Kubernetes 1.36 (RKE2 profile or current K3s)
        |
        v
Kubernetes Gateway API CRDs
        |
        v
AgentGateway CRD Helm chart
        |
        v
AgentGateway control-plane Helm chart
        |
        v
GatewayClass: agentgateway
        |
        v
Gateway: agentgateway-proxy
        |
        v
HTTPRoute
        |
        +------------------------------+
        |                              |
        v                              v
AgentgatewayBackend                MCP backend
        |                              |
        v                              v
vLLM / external LLM              MCP server / tools
```

This is the architecture shown by the AgentGateway installation documentation: Gateway API first, then the AgentGateway CRDs, then the AgentGateway control plane.

Earlier material for this guide referenced AgentGateway `v1.1.0`, which is older. At this review the latest stable AgentGateway release is:

```text
AgentGateway:       v1.5.0
Gateway API:        v1.6.0 for the current standard-channel example
Kubernetes support: 1.32 - 1.37 for AgentGateway 1.5.x
Gateway API support: 1.4 - 1.6 for AgentGateway 1.5.x
Helm:               >= 3.12
```

Our target Kubernetes `1.36.x` therefore fits the current AgentGateway 1.5.x support range.

---

## 1. AgentGateway vs LiteLLM vs Traefik

These products overlap in some areas, but they are not the same thing.

| Component | Main responsibility | Gateway API controller? | GPU required? |
|---|---|---:|---:|
| **AgentGateway** | Kubernetes-native gateway for LLM, MCP, A2A and normal HTTP traffic | **Yes** | No |
| **LiteLLM** | OpenAI-compatible LLM proxy, provider/model routing, budgets and key management | No | No |
| **Traefik** | General Kubernetes ingress/Gateway API traffic | Yes, when enabled | No |
| **vLLM** | Actual model inference | No | Usually yes |

For the AgentGateway path, the clean architecture is:

```text
applications / agents
        |
        v
Kubernetes Gateway API
        |
        v
AgentGateway
        |
        +-----------------------+
        |                       |
        v                       v
LLM backend                  MCP backend
        |                       |
        v                       v
vLLM / cloud LLM          tools / APIs / DBs
        |
        v
GPU worker when local
```

### Do we still need LiteLLM?

Not automatically.

AgentGateway itself supports LLM/provider routing and OpenAI-compatible backends such as vLLM. It also supports AI policies such as model aliases and content-based routing. Therefore a simple AI Factory can use:

```text
client
  |
AgentGateway
  |
vLLM
  |
GPU
```

Keep LiteLLM only if its specific higher-level features are required and provide value beyond AgentGateway. Do not add both layers merely because both are called gateways.

Possible composed design when there is a clear reason:

```text
client
  |
AgentGateway
  |
LiteLLM
  |
vLLM / external providers
```

But start with the smallest architecture that satisfies the actual requirements.

### Do we still need Traefik?

Yes for the repository's existing general application ingress if desired, but **Traefik does not have to be the Gateway API implementation for AgentGateway**.

They can coexist using separate classes:

```text
Traefik
  -> IngressClass: traefik
  -> normal application ingress

AgentGateway
  -> GatewayClass: agentgateway
  -> AI / LLM / MCP / agent traffic
```

Do not enable `providers.kubernetesGateway` in Traefik merely to make AgentGateway work. AgentGateway watches its own Gateway API resources through its own controller.

---

## 2. Prerequisites

Required:

- RKE2 / Kubernetes 1.36.x for this project (the current K3s `v1.36.4+k3s1` repository cluster qualifies);
- `kubectl` configured for the cluster;
- Helm `>= 3.12`;
- Kubernetes Gateway API CRDs;
- working cluster DNS;
- a CNI that supports the networking required by the cluster;
- a way to expose the AgentGateway proxy when external traffic is required;
- at least one backend, such as vLLM, an external LLM provider, an MCP server, or a normal HTTP service.

Required for local NVIDIA-backed inference:

- NVIDIA GPU worker node;
- NVIDIA Linux driver;
- containerd GPU runtime integration;
- NVIDIA GPU Operator or equivalent driver/toolkit/device-plugin stack;
- a model server such as vLLM.

Recommended:

- cert-manager for TLS certificate lifecycle;
- NetworkPolicy-capable CNI;
- Prometheus/Grafana for gateway and inference telemetry;
- External Secrets, Vault, SOPS, or another proper secret-management solution;
- dedicated CPU nodes for gateway/control-plane components and dedicated GPU workers for inference.

AgentGateway itself is a CPU workload. Do not reserve GPU resources for its control plane or gateway proxy unless a specific sidecar/workload requires them.

---

## 3. Pin the current stable versions

Use explicit version pins rather than floating tags:

```bash
export AGENTGATEWAY_VERSION=v1.5.0
export GWAPI_VERSION=1.6.0
```

Check the upstream release before changing the pin:

```bash
helm show chart \
  oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --version "${AGENTGATEWAY_VERSION}"

helm show chart \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --version "${AGENTGATEWAY_VERSION}"
```

Also inspect the values for the exact control-plane chart before production changes:

```bash
helm show values \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --version "${AGENTGATEWAY_VERSION}" \
  > /tmp/agentgateway-values-${AGENTGATEWAY_VERSION}.yaml
```

---

## 4. Install Kubernetes Gateway API CRDs

This is the actual prerequisite for AgentGateway.

For AgentGateway `v1.5.0`, the current standard-channel documentation uses Gateway API `1.6.0`:

```bash
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GWAPI_VERSION}/standard-install.yaml"
```

Verify:

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io

kubectl api-resources | grep -E 'GatewayClass|Gateway|HTTPRoute|ReferenceGrant'
```

Do not install the experimental Gateway API bundle unless an explicitly selected AgentGateway feature requires it.

---

## 5. Install AgentGateway CRDs with Helm

AgentGateway is distributed as **two Helm charts**. The first chart owns AgentGateway's custom resource definitions.

```bash
helm upgrade --install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --create-namespace \
  --namespace agentgateway-system \
  --version "${AGENTGATEWAY_VERSION}" \
  --set controller.image.pullPolicy=Always
```

Verify the release:

```bash
helm status agentgateway-crds -n agentgateway-system
helm list -n agentgateway-system
```

Verify AgentGateway resources are registered:

```bash
kubectl api-resources | grep -i agentgateway
kubectl get crd | grep agentgateway
```

The Gateway API CRDs and the AgentGateway CRDs are separate things:

```text
Gateway API CRDs
  -> GatewayClass
  -> Gateway
  -> HTTPRoute
  -> ReferenceGrant

AgentGateway CRDs
  -> AgentgatewayBackend
  -> AgentGateway-specific policies/configuration
```

Both layers are required for the normal Kubernetes AgentGateway installation.

---

## 6. Install the AgentGateway control plane with Helm

Install the second chart:

```bash
helm upgrade --install agentgateway \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --namespace agentgateway-system \
  --version "${AGENTGATEWAY_VERSION}" \
  --set controller.image.pullPolicy=Always \
  --wait \
  --timeout 10m
```

For production, inspect and place explicit resource, security, availability and monitoring values in a reviewed values file instead of relying only on command-line flags.

Validate:

```bash
kubectl get pods -n agentgateway-system
kubectl get svc -n agentgateway-system
kubectl get gatewayclass
kubectl get gatewayclass agentgateway -o yaml
```

Expected architecture at this point:

```text
agentgateway-system
  |
  +-- agentgateway control-plane Deployment
  |
  +-- GatewayClass: agentgateway
```

The current chart's default GatewayClass name is `agentgateway`.

---

## 7. Create the AgentGateway data-plane Gateway

Installing the control plane does not by itself create the application-facing proxy that routes LLM/MCP traffic. Create a Gateway that references the AgentGateway GatewayClass:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agentgateway-proxy
  namespace: agentgateway-system
spec:
  gatewayClassName: agentgateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

Apply:

```bash
kubectl apply -f agentgateway-proxy.yaml
```

Verify that the controller programs it and creates the proxy resources:

```bash
kubectl get gateway agentgateway-proxy -n agentgateway-system
kubectl describe gateway agentgateway-proxy -n agentgateway-system
kubectl get deployment agentgateway-proxy -n agentgateway-system
kubectl get svc agentgateway-proxy -n agentgateway-system
```

Look for a `Programmed=True` condition on the Gateway.

For local testing when no external address is available:

```bash
kubectl port-forward \
  deployment/agentgateway-proxy \
  -n agentgateway-system \
  8080:80
```

---

## 8. Connect AgentGateway directly to vLLM

AgentGateway can route directly to an OpenAI-compatible vLLM server. LiteLLM is not required for this path.

Assume vLLM is available as:

```text
vllm.ai-inference.svc.cluster.local:8000
```

Create an AgentGateway backend:

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: vllm
  namespace: agentgateway-system
spec:
  ai:
    provider:
      openai:
        model: <vllm-served-model-name>
      host: vllm.ai-inference.svc.cluster.local
      port: 8000
```

Create an `HTTPRoute` that targets that AgentGateway backend:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: vllm
  namespace: agentgateway-system
spec:
  parentRefs:
    - name: agentgateway-proxy
      namespace: agentgateway-system
  rules:
    - backendRefs:
        - name: vllm
          namespace: agentgateway-system
          group: agentgateway.dev
          kind: AgentgatewayBackend
```

Apply:

```bash
kubectl apply -f agentgateway-vllm-backend.yaml
kubectl apply -f agentgateway-vllm-route.yaml
```

Verify:

```bash
kubectl get agentgatewaybackend -n agentgateway-system
kubectl get httproute -n agentgateway-system
kubectl describe httproute vllm -n agentgateway-system
```

Look for:

```text
Accepted=True
ResolvedRefs=True
```

Then test through the gateway. With the local port-forward example:

```bash
curl -sS http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "<vllm-served-model-name>",
    "messages": [
      {"role": "user", "content": "Explain inference in one sentence."}
    ]
  }'
```

The request path is now:

```text
client
  |
Gateway API Gateway
  |
AgentGateway proxy
  |
HTTPRoute
  |
AgentgatewayBackend
  |
vLLM Service
  |
vLLM Pod
  |
NVIDIA GPU
```

---

## 9. MCP through AgentGateway

AgentGateway is also designed to proxy MCP traffic, which is important for an agentic AI Factory.

Conceptually:

```text
agent
  |
AgentGateway
  |
HTTPRoute / AgentgatewayBackend
  |
MCP server
  |
tools / APIs / databases
```

An MCP `AgentgatewayBackend` can target an in-cluster MCP server, while the `HTTPRoute` sends a path such as `/mcp` to that backend.

This means AgentGateway can potentially cover both:

```text
agent -> LLM
agent -> MCP tools
```

through a single Kubernetes-native gateway boundary.

Do not automatically remove the separate IBM ContextForge evaluation from this repository, because the two products have different feature sets and operational models. Compare actual requirements such as registry/discovery, policy, identity, audit, federation and administration before standardizing on one.

---

## 10. TLS with cert-manager

TLS is recommended for production but cert-manager is not required merely to start AgentGateway.

For the existing platform, the preferred certificate manager is cert-manager. The high-level pattern is:

```text
cert-manager
   |
TLS Secret
   |
Gateway HTTPS listener
   |
AgentGateway proxy
```

If cert-manager is expected to reconcile `Gateway` resources, enable Gateway API support in the cert-manager Helm values and ensure the Gateway API CRDs exist before cert-manager starts/restarts.

Example HTTPS listener shape:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agentgateway-proxy
  namespace: agentgateway-system
spec:
  gatewayClassName: agentgateway
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: ai.example.com
      tls:
        mode: Terminate
        certificateRefs:
          - name: agentgateway-tls
      allowedRoutes:
        namespaces:
          from: All
```

The exact certificate issuance design should be validated with the selected cert-manager Issuer/ClusterIssuer and DNS configuration before production exposure.

---

## 11. Gateway API Inference Extension is a separate optional layer

Do not confuse three different things:

```text
Kubernetes Gateway API
  -> REQUIRED for AgentGateway

AgentGateway
  -> gateway implementation/control plane
  -> LLM/MCP/A2A routing

Gateway API Inference Extension
  -> OPTIONAL advanced inference-aware routing
  -> InferencePool + endpoint picker
```

For the first self-hosted vLLM deployment, use:

```text
Gateway API
  |
AgentGateway
  |
HTTPRoute
  |
AgentgatewayBackend
  |
vLLM
```

When one logical model has multiple GPU-backed serving replicas and normal routing is no longer sufficient, AgentGateway can integrate with the Gateway API Inference Extension.

The current official AgentGateway inference example uses:

```text
Gateway API Inference Extension CRDs: v1.5.0
llm-d Router Gateway chart:            v0.9.0
```

and enables support in the AgentGateway Helm chart with:

```bash
--set inferenceExtension.enabled=true
```

That advanced topology becomes:

```text
client
  |
AgentGateway
  |
HTTPRoute
  |
InferencePool
  |
llm-d Router EPP
  |
selected vLLM/model-server Pod
  |
GPU
```

Do not add this layer until multiple replicas and GPU utilization justify the additional control plane.

---

## 12. Coexistence with the existing Traefik deployment

The current repository already runs Traefik. Keep it for existing application ingress.

Recommended migration/evaluation layout:

```text
                         Kubernetes cluster
                                |
          +---------------------+---------------------+
          |                                           |
          v                                           v
       Traefik                                  AgentGateway
IngressClass: traefik                    GatewayClass: agentgateway
          |                                           |
 normal web apps                            LLM / MCP / agent traffic
```

Important rules:

1. Do not turn on Traefik Gateway API merely because AgentGateway needs Gateway API CRDs.
2. Gateway API CRDs are cluster-wide APIs that multiple controllers can use safely through separate GatewayClasses.
3. Keep route ownership explicit: a route should attach to the intended Gateway/GatewayClass.
4. Plan LoadBalancer/external addresses and ports deliberately so Traefik and AgentGateway do not unintentionally compete for the same exposure path.
5. Keep the existing Traefik path operational while AgentGateway is evaluated with one non-critical AI route.

---

## 13. Production Helm values considerations

Before production, inspect the exact pinned values:

```bash
helm show values \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --version "${AGENTGATEWAY_VERSION}" \
  > /tmp/agentgateway-values.yaml
```

Review at minimum:

- `controller.replicaCount`;
- controller resources;
- `controller.horizontalPodAutoscaler`;
- `controller.podDisruptionBudget`;
- pod security context;
- container security context;
- node selectors/affinity/topology spread;
- monitoring integration;
- discovery namespace selectors;
- xDS TLS settings;
- image registry/tag/digest;
- GatewayClass naming;
- `inferenceExtension.enabled` only when intentionally used.

The current chart supports controller HPA, PDB and monitoring options. Treat the defaults as a starting point, not a production capacity plan.

---

## 14. Upgrade procedure

Always upgrade AgentGateway CRDs before the control plane.

```bash
export NEW_AGENTGATEWAY_VERSION=<new-stable-version>
```

Inspect the target charts first:

```bash
helm show chart \
  oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --version "${NEW_AGENTGATEWAY_VERSION}"

helm show chart \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --version "${NEW_AGENTGATEWAY_VERSION}"

helm show values \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --version "${NEW_AGENTGATEWAY_VERSION}" \
  > /tmp/agentgateway-values-new.yaml
```

Upgrade CRDs:

```bash
helm upgrade --install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --namespace agentgateway-system \
  --version "${NEW_AGENTGATEWAY_VERSION}"
```

Then upgrade the control plane using the reviewed production values:

```bash
helm upgrade --install agentgateway \
  oci://cr.agentgateway.dev/charts/agentgateway \
  --namespace agentgateway-system \
  --version "${NEW_AGENTGATEWAY_VERSION}" \
  -f values-production.yaml \
  --wait
```

Verify all existing Gateways and HTTPRoutes after the upgrade.

---

## 15. Uninstall order

Do not delete shared Gateway API CRDs while another controller, such as Traefik Gateway API, still depends on them.

For an AgentGateway-only cleanup:

```text
HTTPRoutes / policies / AgentgatewayBackends
        |
Gateways
        |
AgentGateway control-plane Helm release
        |
AgentGateway CRD Helm release
        |
agentgateway-system namespace
        |
Gateway API CRDs only if nothing else uses them
```

Commands:

```bash
helm uninstall agentgateway -n agentgateway-system
helm uninstall agentgateway-crds -n agentgateway-system
```

Remove the namespace only after confirming that no retained resources or Secrets are required:

```bash
kubectl delete namespace agentgateway-system
```

Remove Gateway API CRDs only when they are genuinely no longer used anywhere in the cluster:

```bash
kubectl delete -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GWAPI_VERSION}/standard-install.yaml"
```

---

## 16. Troubleshooting sequence

Use this order:

```text
1. Are Gateway API CRDs installed?
2. Are AgentGateway CRDs installed?
3. Is the AgentGateway control-plane Pod Ready?
4. Does GatewayClass agentgateway exist?
5. Is the Gateway Programmed=True?
6. Is the HTTPRoute Accepted=True?
7. Are backend references ResolvedRefs=True?
8. Can the AgentGateway proxy resolve/reach vLLM/MCP directly?
9. Is the model/MCP server itself healthy?
10. Only then troubleshoot public DNS/TLS/load-balancer exposure.
```

Useful commands:

```bash
kubectl get gatewayclass
kubectl get gateways -A
kubectl get httproutes -A
kubectl get agentgatewaybackend -A
kubectl get pods,svc -n agentgateway-system
kubectl get events -n agentgateway-system --sort-by=.lastTimestamp
kubectl logs deploy/agentgateway -n agentgateway-system --tail=200
helm status agentgateway -n agentgateway-system
helm get values agentgateway -n agentgateway-system
```

Do not start by restarting Pods. First identify whether the failure is at the API/CRD, controller, Gateway, route, backend, DNS/networking, or model-serving layer.

---

## 17. Recommended adoption for this repository

For the AI Factory, evaluate AgentGateway in this order:

```text
1. Kubernetes 1.36 (RKE2 profile or current K3s)
2. Gateway API CRDs
3. AgentGateway CRDs
4. AgentGateway control plane
5. GatewayClass + Gateway
6. one HTTPRoute
7. one vLLM AgentgatewayBackend
8. validate inference
9. add TLS/auth/policy/observability
10. add MCP only when an agent needs tools
11. add Inference Extension only for multi-replica model serving
```

This gives us a cleaner Kubernetes-native AI gateway experiment than stacking every gateway product at once.

### Recommended initial topology

```text
                       applications / agents
                                |
                                v
                        AgentGateway proxy
                   GatewayClass: agentgateway
                                |
                    +-----------+-----------+
                    |                       |
                    v                       v
              LLM HTTPRoute             MCP HTTPRoute
                    |                       |
                    v                       v
          AgentgatewayBackend       AgentgatewayBackend
                    |                       |
                    v                       v
                  vLLM                  MCP server
                    |
                    v
                 GPU worker
```

Traefik remains available for the repository's ordinary application ingress and does not need to participate in this AI traffic path unless we deliberately choose that topology.

---

## Official references

- AgentGateway project: <https://github.com/agentgateway/agentgateway>
- AgentGateway docs: <https://agentgateway.dev/docs/kubernetes/latest/>
- AgentGateway installation: <https://agentgateway.dev/docs/kubernetes/latest/documentation/quickstart/install/>
- AgentGateway Helm reference: <https://agentgateway.dev/docs/kubernetes/latest/reference/helm/>
- AgentGateway version support: <https://agentgateway.dev/docs/kubernetes/latest/release-notes/versions/>
- AgentGateway vLLM integration: <https://agentgateway.dev/docs/kubernetes/latest/integrations/llm/providers/vllm/>
- AgentGateway LLM docs: <https://agentgateway.dev/docs/kubernetes/latest/documentation/llm/>
- AgentGateway MCP docs: <https://agentgateway.dev/docs/kubernetes/latest/documentation/mcp/>
- AgentGateway inference routing: <https://agentgateway.dev/docs/kubernetes/latest/documentation/llm/inference/inference-routing/>
- Kubernetes Gateway API: <https://gateway-api.sigs.k8s.io/>
- Gateway API Inference Extension: <https://gateway-api-inference-extension.sigs.k8s.io/>
