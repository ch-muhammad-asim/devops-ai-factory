# MCP Gateway on Kubernetes

> **Research review:** 2026-09-13. This guide targets the repository's production AI Factory direction: Ubuntu 24.04 LTS, RKE2 / Kubernetes 1.36.x, containerd, Traefik, cert-manager, Argo CD, NVIDIA GPU workers, LiteLLM for model/API routing, and vLLM/KServe/KubeRay for inference. The repository as committed today runs K3s `v1.36.4+k3s1` (Kubernetes 1.36) on a single Ubuntu 26.04 LTS `t3.medium` EC2 node with no GPU; see [`../kubernetes-distribution-recommendation.md`](../kubernetes-distribution-recommendation.md) for why the production profile differs.
>
> The implementation selected for this guide is **IBM ContextForge** (`IBM/mcp-context-forge`) because it currently provides a production-oriented MCP gateway/registry, a maintained Kubernetes Helm chart, PostgreSQL/Redis support, authentication, policy/guardrail features, observability, HA/HPA options, and a current GA release.

## Decision

An **MCP Gateway is not required to build the base AI Factory**.

The first useful AI Factory can run without one:

```text
applications
    |
    v
LiteLLM Gateway
    |
    v
vLLM / KServe / KubeRay
    |
    v
GPU workers
```

Add an MCP Gateway when applications or agents begin using **tools, resources, prompts, APIs, databases, SaaS services, or several MCP servers** and the platform needs centralized discovery, authentication, authorization, policy, auditing and routing.

For this project the recommended adoption path is:

```text
Stage 1
Kubernetes 1.36 (RKE2 or K3s) + GPU Operator + vLLM + LiteLLM
        |
        v
working model inference

Stage 2
one or two MCP servers connected directly to an agent
        |
        v
prove the tool-calling use case

Stage 3
multiple MCP servers / agents / teams
        |
        v
add ContextForge MCP Gateway

Stage 4
HA + external PostgreSQL/Redis + OAuth/Vault + full observability
```

So the answer is:

> **No, MCP Gateway is not mandatory for an AI Factory. It becomes valuable when the AI Factory becomes agentic and needs to operate many tools safely and consistently.**

---

## 1. What is MCP?

**MCP (Model Context Protocol)** is a protocol for connecting AI clients/agents to capabilities outside the model itself.

Those capabilities normally fall into three groups:

```text
Tools
  -> actions an agent can execute
  -> query database
  -> create ticket
  -> call API
  -> search repository
  -> send message

Resources
  -> information the agent can read
  -> files
  -> documents
  -> API data
  -> database records

Prompts
  -> reusable prompt templates/workflows exposed by a server
```

Without MCP, every AI application can end up implementing a different custom integration for every external system.

With MCP:

```text
AI application / agent
          |
          v
       MCP client
          |
          v
       MCP server
          |
          v
API / DB / Git / Slack / filesystem / internal service
```

MCP does **not** replace the LLM or inference runtime. It connects the agent to external capabilities.

---

## 2. What is an MCP Gateway?

If there is only one trusted MCP server, an application can connect to it directly.

As the number of tools grows, direct connections become difficult to operate:

```text
agent A ---> MCP server 1
        ---> MCP server 2
        ---> MCP server 3

agent B ---> MCP server 1
        ---> MCP server 4
        ---> MCP server 5
```

Each application now has to understand endpoints, authentication, access policy, discovery and failures for every MCP server.

An MCP Gateway creates a controlled platform boundary:

```text
agents / AI applications
          |
          v
      MCP Gateway
          |
     +----+----+----------------+
     |         |                |
     v         v                v
MCP server  MCP server      REST/gRPC/API
Git tools   DB tools        enterprise services
```

The gateway can provide a central place for:

- MCP server/tool registration and discovery;
- authentication and authorization;
- team/tenant access control;
- centralized policy and guardrails;
- tool/resource/prompt routing;
- session handling;
- protocol translation/integration;
- auditability;
- observability and tracing;
- rate limiting and operational controls;
- credential management/integration;
- a stable endpoint for agent applications.

---

## 3. MCP Gateway vs LLM Gateway vs LLMKube

These components solve different problems.

| Component | Responsibility | GPU required? | Recommended here? |
|---|---|---:|---|
| **LiteLLM Gateway** | Model/API routing, model aliases, provider abstraction, budgets, retries/fallbacks | No | Yes when exposing models to applications |
| **LLMKube** | Kubernetes operator for deploying/managing inference runtimes and model services | Controller: No; model Pods: Yes when accelerated | Optional; evaluate after basic inference works |
| **MCP Gateway / ContextForge** | Tool/resource/prompt/API gateway and registry for agents | No | Add when agentic tool integration becomes operationally significant |
| **vLLM/KServe/KubeRay** | Executes model inference | Usually yes | Yes according to workload |

A clean architecture is:

```text
                              +-------------------------+
                              |      AI application     |
                              +-----------+-------------+
                                          |
                        +-----------------+------------------+
                        |                                    |
                        v                                    v
               LiteLLM Gateway                         MCP Gateway
               model requests                         tool requests
                        |                                    |
                        v                                    v
               vLLM / KServe                     MCP servers / APIs / DBs
                        |
                        v
                   NVIDIA GPU
```

The LLM Gateway answers **"which model should handle this request?"**

The MCP Gateway answers **"which approved tool/resource should this agent access, and under what policy?"**

---

## 4. Why ContextForge for this project?

Several MCP gateway implementations exist. For this repository the current recommendation is **IBM ContextForge** because it fits the Kubernetes-first, self-hosted design and currently provides an official full-stack Helm chart.

The project describes itself as an AI gateway/registry/proxy in front of MCP, A2A and REST/gRPC APIs. It provides a unified endpoint with centralized discovery, management, security and observability capabilities.

The current GA release at this review is:

```text
ContextForge release: v1.0.10
Helm chart:          1.0.10
Chart appVersion:   1.0.10
Release date:       2026-09-07
```

The `v1.0.10` release focuses on OAuth security, observability, plugin-context propagation, Vault support, reliability and dependency-security updates.

The upstream chart declares Kubernetes `>=1.21`, while the current Helm documentation recommends Kubernetes `>=1.23`. Our target **RKE2 / Kubernetes 1.36.x**, like the current K3s `v1.36.4+k3s1` repository cluster, is therefore comfortably above the required level.

Official project:

- <https://github.com/IBM/mcp-context-forge>
- <https://ibm.github.io/mcp-context-forge/>
- Latest releases: <https://github.com/IBM/mcp-context-forge/releases>

---

## 5. Recommended AI Factory architecture

```text
                            Internet / internal clients
                                      |
                                      v
                                Traefik + TLS
                                      |
                    +-----------------+------------------+
                    |                                    |
                    v                                    v
              LiteLLM Gateway                      ContextForge
              model API layer                      MCP Gateway
                    |                                    |
           +--------+--------+                 +---------+----------+
           |                 |                 |         |          |
           v                 v                 v         v          v
         vLLM             KServe          Git MCP    DB MCP    REST/gRPC
           |                 |             server     server      APIs
           +--------+--------+
                    |
                    v
              GPU worker pool
                    |
                    v
            physical NVIDIA GPUs
```

ContextForge should normally run on **CPU nodes**. It is a gateway/control-plane workload; it does not perform GPU inference.

---

## 6. Requirements

### Required

- RKE2 / Kubernetes 1.36.x for this project (the current K3s `v1.36.4+k3s1` repository cluster qualifies);
- Helm 3;
- `kubectl` configured for the target cluster;
- a working StorageClass with dynamic provisioning;
- Traefik or another ingress controller;
- DNS if the gateway is exposed through a hostname;
- TLS certificate management (cert-manager is already the preferred platform component here);
- sufficient CPU/memory for ContextForge, PostgreSQL and Redis;
- strong authentication secrets.

### Recommended for production

- at least two ContextForge gateway replicas;
- HPA enabled;
- PostgreSQL persistence and backups;
- Redis for shared cache/session behavior;
- NetworkPolicy-capable CNI;
- Prometheus + Grafana / OpenTelemetry;
- external secret management or encrypted GitOps secrets;
- OAuth/OIDC or another centralized identity provider;
- controlled egress from the gateway;
- sandboxed/isolated MCP server workloads;
- separate CPU and GPU worker pools.

### Not required

- NVIDIA GPU on the ContextForge Pod;
- NVIDIA AI Enterprise;
- LLMKube;
- KServe;
- a public internet endpoint.

The MCP Gateway can be entirely internal.

---

## 7. Current Helm installation method

The upstream project currently documents the **local chart from the Git repository** as the supported Helm path, plus pushing the packaged chart to your own OCI registry. There is no hosted upstream Helm repository, so this guide does not assume one exists.

For reproducibility, clone the exact release tag instead of `main`:

```bash
export CONTEXTFORGE_VERSION=v1.0.10

git clone \
  --branch "${CONTEXTFORGE_VERSION}" \
  --depth 1 \
  https://github.com/IBM/mcp-context-forge.git

cd mcp-context-forge/charts/mcp-stack
```

Verify the pinned chart:

```bash
grep -E '^(version|appVersion|kubeVersion):' Chart.yaml
helm lint .
```

Expected release/chart line for this review:

```text
version: 1.0.10
appVersion: "1.0.10"
```

Do not deploy production directly from a floating `main` checkout.

---

## 8. Pre-flight checks

```bash
kubectl config current-context
kubectl cluster-info
kubectl version
helm version
kubectl get nodes -o wide
kubectl get storageclass
kubectl get pods -A
```

Verify Traefik and cert-manager:

```bash
kubectl get pods -n traefik
kubectl get pods -n cert-manager
kubectl get clusterissuer,issuer -A
```

Verify that the current user can create resources:

```bash
kubectl auth can-i create namespace
kubectl auth can-i create deployment -n default
kubectl auth can-i create secret -n default
kubectl auth can-i create ingress -n default
```

Create a dedicated namespace:

```bash
kubectl create namespace mcp-gateway
kubectl label namespace mcp-gateway app.kubernetes.io/part-of=ai-factory --overwrite
```

---

## 9. Production values for this AI Factory

Create a non-secret override file such as `values-production.yaml` **outside Git until reviewed**:

```yaml
serviceAccount:
  create: true
  automountServiceAccountToken: false

networkPolicies:
  enabled: true

mcpContextForge:
  replicaCount: 2

  image:
    repository: ghcr.io/ibm/mcp-context-forge
    tag: "v1.0.10"
    pullPolicy: IfNotPresent

  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80

  service:
    type: ClusterIP
    port: 80

  resources:
    requests:
      cpu: 500m
      memory: 768Mi
    limits:
      cpu: "2"
      memory: 2Gi

  ingress:
    enabled: true
    className: traefik
    host: mcp.example.com
    path: /
    pathType: Prefix
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls:
      enabled: true
      secretName: mcp-gateway-tls

  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

  config:
    APP_DOMAIN: "https://mcp.example.com"
    SSRF_ALLOW_PRIVATE_NETWORKS: "false"
    SSRF_ALLOWED_NETWORKS: '["10.42.0.0/16","10.43.0.0/16"]'
    SSRF_DNS_FAIL_CLOSED: "true"

postgres:
  enabled: true
  persistence:
    enabled: true
    size: 10Gi

pgadmin:
  enabled: false

redisCommander:
  enabled: false
```

Replace:

```text
mcp.example.com
letsencrypt-prod
10.42.0.0/16
10.43.0.0/16
```

with the actual DNS, issuer, Pod CIDR and Service CIDR for the cluster.

### Important SSRF rule

ContextForge intentionally defaults to strict SSRF protection. Private addresses are blocked unless explicitly allowed.

For production, **do not simply set**:

```yaml
SSRF_ALLOW_PRIVATE_NETWORKS: "true"
```

just to make in-cluster MCP services work.

Instead, keep private networks blocked globally and allow only the exact Kubernetes/network CIDRs required by approved MCP servers:

```yaml
mcpContextForge:
  config:
    SSRF_ALLOW_PRIVATE_NETWORKS: "false"
    SSRF_ALLOWED_NETWORKS: '["<approved-cidr-1>","<approved-cidr-2>"]'
    SSRF_DNS_FAIL_CLOSED: "true"
```

This matters because an MCP gateway is deliberately allowed to make outbound requests to tools and services. Egress must be treated as a security boundary.

---

## 10. Secrets

Do not commit passwords, JWT signing keys or encryption keys into this repository.

ContextForge `v1.0.10` fails closed for known default/weak passwords when authentication features are enabled, so real production secrets are required.

At minimum configure strong values for:

```text
PLATFORM_ADMIN_EMAIL
PLATFORM_ADMIN_PASSWORD
DEFAULT_USER_PASSWORD
BASIC_AUTH_PASSWORD      (if Basic Auth is enabled)
JWT_SECRET_KEY
AUTH_ENCRYPTION_SECRET
```

Generate values locally:

```bash
openssl rand -hex 32
openssl rand -base64 32
```

For a one-time manual installation, create a temporary Helm secret-values file with restrictive permissions:

```bash
umask 077
cat > /tmp/mcp-gateway-secrets.yaml <<'EOF'
mcpContextForge:
  secret:
    PLATFORM_ADMIN_EMAIL: "admin@example.com"
    PLATFORM_ADMIN_PASSWORD: "REPLACE_ME"
    DEFAULT_USER_PASSWORD: "REPLACE_ME"
    BASIC_AUTH_PASSWORD: "REPLACE_ME"
    JWT_SECRET_KEY: "REPLACE_ME_WITH_64_HEX_CHARS_OR_STRONGER"
    AUTH_ENCRYPTION_SECRET: "REPLACE_ME_WITH_A_STRONG_SECRET"
EOF

chmod 600 /tmp/mcp-gateway-secrets.yaml
```

Replace every placeholder before installation.

For GitOps/production, prefer a dedicated secret solution such as:

- External Secrets Operator + cloud secret manager;
- SOPS-encrypted secrets;
- Sealed Secrets;
- Vault.

Do not place production credentials in normal Helm values committed to Git.

---

## 11. Render before installing

Validate the chart and the production overrides:

```bash
helm lint . -f values-production.yaml
```

Render locally:

```bash
helm template mcp-gateway . \
  --namespace mcp-gateway \
  -f values-production.yaml \
  -f /tmp/mcp-gateway-secrets.yaml \
  > /tmp/mcp-gateway-rendered.yaml
```

Inspect important resources:

```bash
grep -n '^kind:' /tmp/mcp-gateway-rendered.yaml
kubectl apply --dry-run=server -f /tmp/mcp-gateway-rendered.yaml
```

Do not commit `/tmp/mcp-gateway-rendered.yaml` because rendered Secret objects may contain sensitive data.

---

## 12. Install with Helm

From the pinned `charts/mcp-stack` directory:

```bash
helm upgrade --install mcp-gateway . \
  --namespace mcp-gateway \
  --create-namespace \
  -f values-production.yaml \
  -f /tmp/mcp-gateway-secrets.yaml \
  --wait \
  --timeout 30m
```

After successful installation, remove the temporary secret file:

```bash
rm -f /tmp/mcp-gateway-secrets.yaml
```

Check release state:

```bash
helm status mcp-gateway -n mcp-gateway
helm list -n mcp-gateway
kubectl get all -n mcp-gateway
kubectl get ingress -n mcp-gateway
kubectl get pvc -n mcp-gateway
```

---

## 13. Verify the gateway

### Pod readiness

```bash
kubectl get pods -n mcp-gateway -w
```

### Logs

```bash
kubectl logs -n mcp-gateway \
  deployment/mcp-gateway-mcp-stack-mcpgateway \
  --tail=200
```

### Port-forward

```bash
kubectl port-forward \
  -n mcp-gateway \
  svc/mcp-gateway-mcp-stack-mcpgateway \
  4444:80
```

Then check:

```bash
curl -fsS http://127.0.0.1:4444/health
curl -fsS http://127.0.0.1:4444/ready
```

The Admin UI is normally available at:

```text
http://127.0.0.1:4444/admin
```

or through the configured TLS hostname:

```text
https://mcp.example.com/admin
```

Do not expose the Admin UI publicly unless there is a clear need and strong identity/access controls are in place.

---

## 14. Add MCP servers

The MCP Gateway does not replace MCP servers. It registers and fronts them.

Example topology:

```text
ContextForge
    |
    +--> Git MCP server
    |
    +--> Jira MCP server
    |
    +--> PostgreSQL MCP server
    |
    +--> internal REST API
    |
    +--> internal gRPC service
```

Use the ContextForge Admin UI/API to register only MCP servers that have been reviewed and approved.

For in-cluster services, the gateway will typically connect through Kubernetes DNS:

```text
http://service-name.namespace.svc.cluster.local:<port>/...
```

Because these are private addresses, ensure the destination falls inside the explicit `SSRF_ALLOWED_NETWORKS` allowlist.

### Security rule for MCP servers

Treat an MCP server as executable integration code, not as a harmless catalog entry.

Do not run untrusted MCP servers with:

- host filesystem access;
- host networking;
- privileged containers;
- broad Kubernetes RBAC;
- cloud administrator credentials;
- unrestricted egress.

Use separate namespaces, NetworkPolicies, non-root containers, read-only filesystems, least-privilege identities and sandboxing where appropriate.

---

## 15. Integration with LiteLLM

LiteLLM and ContextForge are complementary.

A typical agent request is:

```text
User
  |
  v
Agent application
  |
  +------------------------+
  |                        |
  v                        v
LiteLLM                 ContextForge
  |                        |
  v                        v
vLLM/model            MCP tools/resources
  |                        |
 GPU                   APIs / databases
```

The agent uses LiteLLM for model inference and ContextForge for controlled tool access.

Do not route model-token traffic through the MCP Gateway merely because both components are called gateways. Keep model routing and tool routing as separate responsibilities.

---

## 16. Integration with LLMKube

If LLMKube is adopted later:

```text
LiteLLM
   |
   v
LLMKube-managed inference services
   |
   v
GPU workers

ContextForge
   |
   v
MCP servers / enterprise tools
```

LLMKube manages model/inference workloads. ContextForge manages agent-facing tool/resource access. Neither replaces the other.

---

## 17. Traefik and TLS

This repository already uses Traefik and cert-manager, so the simplest path is to use the chart's normal Kubernetes Ingress with:

```yaml
mcpContextForge:
  ingress:
    enabled: true
    className: traefik
    host: mcp.example.com
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls:
      enabled: true
      secretName: mcp-gateway-tls
```

Verify:

```bash
kubectl describe ingress -n mcp-gateway
kubectl get certificate -n mcp-gateway
kubectl get secret mcp-gateway-tls -n mcp-gateway
```

For advanced Traefik Middleware, IP allowlists, forward-auth or custom routing, disable the chart ingress and manage an `IngressRoute` separately through GitOps.

---

## 18. PostgreSQL and Redis

The upstream Helm chart can deploy PostgreSQL and Redis with the gateway.

That is useful for the first production-like deployment because the complete stack can be managed as one release.

For a more critical production environment, evaluate moving state to independently managed PostgreSQL/Redis so that:

- gateway lifecycle is separated from database lifecycle;
- backups and restore are easier to reason about;
- database upgrades are independent;
- HA and maintenance can follow database-specific practices;
- deleting the Helm release cannot accidentally become a data-loss event.

At minimum:

```bash
kubectl get pvc -n mcp-gateway
kubectl get pv
```

and verify the StorageClass reclaim policy before trusting the bundled database with important configuration/state.

Back up PostgreSQL before any major ContextForge upgrade.

---

## 19. Observability

The chart supports gateway metrics and can create a ServiceMonitor when Prometheus Operator is present.

If kube-prometheus-stack/Prometheus Operator is installed:

```yaml
mcpContextForge:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

The metrics endpoint requires authentication in the current chart, so configure the metrics token/Secret according to upstream guidance before enabling production scraping.

Also monitor:

- HTTP request rate;
- error rate;
- request latency;
- MCP upstream failures;
- auth failures;
- PostgreSQL health;
- Redis health;
- gateway replica/HPA state;
- ingress/TLS errors;
- denied SSRF destinations;
- audit events;
- OpenTelemetry traces when enabled.

Useful checks:

```bash
kubectl get hpa -n mcp-gateway
kubectl top pods -n mcp-gateway
kubectl get events -n mcp-gateway --sort-by='.lastTimestamp'
```

---

## 20. HA and scaling

The gateway is a CPU service, so scaling it is much cheaper than scaling GPU inference capacity.

Recommended initial production values:

```text
ContextForge replicas: 2
HPA min:              2
HPA max:              6
PostgreSQL:           persistent
Redis:                enabled
Traefik:              TLS ingress
```

This is separate from GPU scaling:

```text
MCP Gateway replicas
      !=
GPU inference replicas
```

A surge in tool calls may require more ContextForge replicas even if GPU load is unchanged. A surge in token generation may require more vLLM/GPU capacity even if MCP traffic is unchanged.

Scale and alert on those layers independently.

---

## 21. Security baseline

For an AI Factory, an MCP Gateway is a high-value security boundary because tools can perform real actions.

Minimum controls:

1. TLS everywhere outside the namespace.
2. Strong admin and JWT secrets.
3. OAuth/OIDC for humans and applications where possible.
4. No weak/default passwords.
5. Keep SSRF private-network access disabled by default.
6. Allow only explicit internal CIDRs/endpoints.
7. Use NetworkPolicies for ingress and egress.
8. Run gateway and MCP servers as non-root.
9. Do not grant GPU nodes or MCP tool Pods unnecessary Kubernetes RBAC.
10. Keep platform/admin UI access private or tightly restricted.
11. Audit registrations and tool access.
12. Rotate credentials.
13. Use Vault/secret-manager integrations for sensitive downstream credentials.
14. Never give untrusted MCP servers unrestricted host filesystem or shell access.
15. Review tool descriptions and schemas before exposing them to autonomous agents.

Remember that prompt injection can cause an agent to *ask* for a dangerous tool call. Authentication, authorization and server-side policy must protect the action even when the model makes a bad decision.

---

## 22. GitOps with Argo CD

For this repository, the long-term production pattern should be declarative.

Because the official project currently documents use of a local chart checkout, practical GitOps options are:

1. vendor the **pinned chart version** into a dedicated platform repository;
2. package the pinned chart and push it to an internal OCI Helm registry;
3. consume a future official upstream Helm repository when it becomes available and pin the exact chart version.

Do not point Argo CD at upstream `main` without a release pin.

A clean dependency order is:

```text
Kubernetes 1.36 (RKE2 profile or current K3s)
  |
Traefik + cert-manager
  |
monitoring / secret management
  |
ContextForge MCP Gateway
  |
approved MCP servers
  |
agent applications
```

---

## 23. Upgrade procedure

Before upgrading:

```bash
helm history mcp-gateway -n mcp-gateway
kubectl get pods -n mcp-gateway
kubectl get pvc -n mcp-gateway
```

Then:

1. read the upstream release notes;
2. check breaking changes;
3. back up PostgreSQL;
4. clone the new release tag;
5. compare `values.yaml` and `values.schema.json`;
6. render the chart;
7. perform a server-side dry run;
8. upgrade;
9. validate health, auth, registrations and MCP traffic.

Example:

```bash
helm upgrade mcp-gateway . \
  --namespace mcp-gateway \
  -f values-production.yaml \
  -f /tmp/mcp-gateway-secrets.yaml \
  --wait \
  --timeout 30m
```

Never use an unpinned `latest` image during a production upgrade.

---

## 24. Rollback

Inspect history:

```bash
helm history mcp-gateway -n mcp-gateway
```

Rollback the Kubernetes release:

```bash
helm rollback mcp-gateway <REVISION> \
  --namespace mcp-gateway \
  --wait \
  --timeout 30m
```

A Helm rollback cannot automatically reverse every database migration. Read the release's migration notes and maintain a database restore path.

---

## 25. Uninstall

```bash
helm uninstall mcp-gateway -n mcp-gateway
```

Before deleting the namespace:

```bash
kubectl get pvc -n mcp-gateway
kubectl get pv
```

Do not delete PVCs/databases until required data has been backed up or intentionally retired.

---

## 26. Troubleshooting

### Gateway Pod does not start

```bash
kubectl get pods -n mcp-gateway
kubectl describe pod -n mcp-gateway <pod>
kubectl logs -n mcp-gateway <pod> --previous
```

Common causes:

- weak/default auth password rejected by `v1.0.10`;
- missing JWT/encryption secret;
- PostgreSQL unavailable;
- migration failure;
- PVC cannot bind;
- incorrect configuration.

### Registered in-cluster MCP server is blocked

Check SSRF policy first.

```text
SSRF_ALLOW_PRIVATE_NETWORKS=false
+
SSRF_ALLOWED_NETWORKS does not include target CIDR
=
expected block
```

Add only the required CIDR instead of disabling SSRF protection globally.

### Ingress returns 404/502

```bash
kubectl get ingress -n mcp-gateway
kubectl describe ingress -n mcp-gateway
kubectl get svc,endpoints -n mcp-gateway
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=200
```

### Certificate not ready

```bash
kubectl get certificate,certificaterequest,challenge,order -n mcp-gateway
kubectl describe certificate mcp-gateway-tls -n mcp-gateway
```

### HPA shows unknown metrics

Ensure Metrics Server is available:

```bash
kubectl top pods -n mcp-gateway
kubectl get apiservice | grep metrics
```

---

## 27. Do we really need it?

Use this decision table.

| Situation | MCP Gateway? |
|---|---|
| Only training/inference | **No** |
| vLLM behind LiteLLM | **No** |
| One application calling one trusted MCP server | Usually no |
| A few experimental MCP servers | Probably no |
| Multiple agents share the same tools | **Useful** |
| Multiple teams need different tool permissions | **Yes** |
| Central tool discovery/registry is required | **Yes** |
| OAuth/RBAC/auditing across MCP tools is required | **Yes** |
| Many MCP servers need one stable endpoint | **Yes** |
| Agents access sensitive enterprise systems | **Strongly recommended** |
| Need guardrails and centralized credential handling | **Strongly recommended** |

For this repository:

> **Do not make ContextForge a day-one dependency of GPU inference. Add it when the AI Factory starts hosting agentic workloads that call real tools.**

That keeps the first platform understandable while preserving a clean path toward a governed agent platform.

---

## 28. Recommended final architecture

```text
Ubuntu 24.04 LTS
        |
RKE2 / Kubernetes 1.36.x
        |
        +------------------------------------------------------+
        |                                                      |
        v                                                      v
CPU platform workers                                     GPU workers
        |                                                      |
        +-- Traefik                                            +-- GPU Operator
        +-- cert-manager                                       +-- vLLM/KServe
        +-- Argo CD                                            +-- model inference
        +-- LiteLLM
        +-- ContextForge MCP Gateway (when needed)
        +-- PostgreSQL / Redis
        +-- monitoring
                 |
                 v
          approved MCP servers
                 |
       +---------+----------+
       |         |          |
       v         v          v
     Git       DB/API     SaaS/internal tools
```

This is the target topology. The repository as committed today is one Ubuntu 26.04 LTS `t3.medium` EC2 node running K3s `v1.36.4+k3s1` with Traefik, cert-manager and Argo CD, and no GPU node.

This separation is intentional:

- **RKE2** orchestrates the platform (K3s `v1.36.4+k3s1` in the current repository);
- **GPU Operator** exposes accelerators;
- **vLLM/KServe/KubeRay** run models;
- **LiteLLM** provides the model API gateway;
- **ContextForge** provides the MCP/tool gateway;
- **MCP servers** integrate external systems;
- **Traefik** is the network entry point;
- **cert-manager** manages TLS;
- **Argo CD** manages declarative platform delivery.

---

## Official references

- ContextForge repository: <https://github.com/IBM/mcp-context-forge>
- ContextForge documentation: <https://ibm.github.io/mcp-context-forge/>
- ContextForge Helm deployment: <https://ibm.github.io/mcp-context-forge/latest/deployment/helm/>
- ContextForge releases: <https://github.com/IBM/mcp-context-forge/releases>
- ContextForge `v1.0.10` release: <https://github.com/IBM/mcp-context-forge/releases/tag/v1.0.10>
- Helm chart source: <https://github.com/IBM/mcp-context-forge/tree/v1.0.10/charts/mcp-stack>
- Model Context Protocol: <https://modelcontextprotocol.io/>
