# LLM Gateway on Kubernetes

> **Research review:** 2026-09-13. This guide targets the repository's production AI Factory direction: Ubuntu 24.04 LTS, RKE2 / Kubernetes 1.36.x, containerd, NVIDIA GPU workers, vLLM/KServe/KubeRay for inference, Traefik for north-south routing, cert-manager for TLS, and Helm for application installation. The repository as committed today runs K3s `v1.36.4+k3s1` (Kubernetes 1.36) on a single Ubuntu 26.04 LTS `t3.medium` EC2 node with no GPU; see [`../kubernetes-distribution-recommendation.md`](../kubernetes-distribution-recommendation.md) for why the production profile differs.

## Decision

For this AI Factory, use **LiteLLM Proxy as the first LLM/AI Gateway**.

The gateway is not required to make one vLLM model work, but it becomes valuable as soon as the platform needs a stable API in front of one or more inference backends, centralized authentication, model aliases, rate limits, usage tracking, fallbacks, or routing between local and external models.

Recommended request path:

```text
client / application
        |
        v
Traefik + TLS
        |
        v
LiteLLM Gateway
        |
        +------------------------------+
        |                              |
        v                              v
local vLLM / KServe / Ray Serve   external provider if required
        |
        v
Kubernetes GPU worker
        |
        v
physical NVIDIA GPU
```

LiteLLM itself is a **CPU workload**. Do not reserve a GPU for the gateway. GPUs belong to the inference servers behind it.

## Why LiteLLM first

LiteLLM Proxy provides an OpenAI-compatible gateway in front of many LLM providers and OpenAI-compatible servers. For this project it gives a useful separation of responsibilities:

```text
Traefik
  -> public HTTP/TLS entry point

LiteLLM
  -> AI API authentication
  -> model aliases
  -> model/provider routing
  -> retries/fallbacks
  -> rate limits / budgets
  -> usage and spend tracking
  -> one OpenAI-compatible API for applications

vLLM / KServe / KubeRay
  -> actual model inference
  -> GPU execution
```

This is different from Kubernetes Gateway API Inference Extension. LiteLLM is the higher-level **AI/LLM gateway**. Gateway API Inference Extension is for **inference-aware endpoint selection** among self-hosted model-serving replicas. They can be composed later.

## Current version pin

As of this review, the latest stable LiteLLM Helm package published in the upstream GHCR package registry is:

```text
LiteLLM Helm chart: 1.100.1
LiteLLM stable application/image line: 1.100.1
```

Stable `1.99.0` and `1.100.0` were published before it in September 2026; this guide pins `1.100.1` and is re-verified against that chart's `values.yaml`.

Do not use `latest`, `main-latest`, or an RC tag in the production profile. Re-check the upstream release/package page before changing the pin.

Official OCI chart:

```text
oci://ghcr.io/berriai/litellm-helm
```

## Platform requirements

### Required

- Kubernetes cluster. This project targets **RKE2 / Kubernetes 1.36.x** for the production profile; the current repository cluster, K3s `v1.36.4+k3s1`, is also Kubernetes 1.36 and works for evaluation.
- `kubectl` configured for the target cluster.
- Helm 3 with OCI registry support. Helm 3.8+ has OCI support enabled by default; use a current supported Helm 3 release.
- Working cluster DNS/CoreDNS.
- A default StorageClass if using in-cluster PostgreSQL.
- Traefik or another ingress/gateway implementation if the LLM Gateway will be exposed outside the cluster.
- cert-manager plus a working Issuer/ClusterIssuer if TLS certificates are automated.
- At least one model backend, for example vLLM, KServe, Ray Serve, NVIDIA NIM, Ollama, or an external provider.
- Kubernetes Secrets for all API keys, database credentials, and the LiteLLM master key.

### Required for the local GPU path

LiteLLM itself does not require GPU support. The model server does.

For NVIDIA-backed local inference:

```text
physical NVIDIA GPU
        |
Ubuntu GPU worker
        |
NVIDIA driver
        |
RKE2 or K3s / containerd
        |
NVIDIA GPU Operator or manual runtime/device-plugin stack
        |
Kubernetes advertises nvidia.com/gpu
        |
vLLM / KServe / Ray Serve
        |
LiteLLM routes requests to the model server
```

### Recommended production dependencies

- PostgreSQL for LiteLLM state and management features.
- Redis when running multiple LiteLLM replicas and requiring coordinated rate limits, spend tracking, and distributed locking.
- Prometheus/Grafana for metrics.
- External Secrets, SOPS, Vault, AWS Secrets Manager integration, or another secret-management system instead of committing credentials to Git.
- At least two CPU worker nodes for a highly available gateway deployment.

## Capacity guidance

The upstream LiteLLM Helm values currently document approximately **1 CPU and 4 GiB memory per proxy worker** for a database-connected production proxy. Treat that as a starting point, then size from measurements.

A reasonable initial production request is:

```yaml
resources:
  requests:
    cpu: "1"
    memory: 4Gi
  limits:
    cpu: "2"
    memory: 4Gi
```

This is for the gateway only. It is separate from GPU/model memory requirements.

## Namespace layout

A clean separation is:

```text
llm-gateway
  -> LiteLLM
  -> gateway secrets
  -> optional bundled Redis/PostgreSQL for non-production/test

ai-inference
  -> vLLM / KServe / KubeRay
  -> GPU-backed model Pods

traefik
  -> north-south traffic

cert-manager
  -> TLS certificates

monitoring
  -> Prometheus / Grafana / DCGM
```

## 1. Verify the cluster

```bash
kubectl version
kubectl get nodes -o wide
kubectl get pods -A
kubectl get storageclass
helm version
```

For an NVIDIA inference backend also verify:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu
```

A GPU worker should report one or more allocatable `nvidia.com/gpu` resources after GPU integration is healthy.

## 2. Inspect the official Helm chart before installation

Pin the version explicitly:

```bash
export LITELLM_CHART_VERSION=1.100.1
```

Inspect chart metadata:

```bash
helm show chart \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${LITELLM_CHART_VERSION}"
```

Inspect the exact values for that pinned version:

```bash
helm show values \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${LITELLM_CHART_VERSION}" \
  > /tmp/litellm-values-${LITELLM_CHART_VERSION}.yaml
```

This step matters because Helm values can change between LiteLLM releases.

## 3. Create the namespace

```bash
kubectl create namespace llm-gateway
```

The Helm command later also uses `--create-namespace`, so this explicit command is optional. Creating it first is convenient for Secrets.

## 4. Create the LiteLLM master-key Secret

Generate a strong master key locally:

```bash
export LITELLM_MASTER_KEY="sk-$(openssl rand -hex 32)"
```

Create the Secret without committing the value to Git:

```bash
kubectl -n llm-gateway create secret generic litellm-master-key \
  --from-literal=master-key="${LITELLM_MASTER_KEY}"
```

Do not place this value in `values.yaml`, Terraform variables committed to Git, or repository documentation.

## 5. Create the vLLM/backend Secret

If the internal vLLM server uses an API key:

```bash
export VLLM_API_KEY="$(openssl rand -hex 32)"

kubectl -n llm-gateway create secret generic litellm-model-secrets \
  --from-literal=VLLM_API_KEY="${VLLM_API_KEY}"
```

Configure the same key on the vLLM side.

If the model server is completely private and does not use an API key, LiteLLM can still reach it, but production deployments should secure access with network policy and/or backend authentication.

## 6. Prepare PostgreSQL

### Production recommendation

Use a durable PostgreSQL deployment managed independently from the LLM Gateway release. On AWS that may be RDS/Aurora PostgreSQL; on-prem it may be a PostgreSQL operator or a separately managed PostgreSQL cluster.

Create a dedicated database and user, for example:

```text
database: litellm
user:     litellm
port:     5432
```

Create the Kubernetes Secret expected by the Helm values used in this guide:

```bash
kubectl -n llm-gateway create secret generic litellm-db \
  --from-literal=username='litellm' \
  --from-literal=password='<strong-database-password>'
```

Replace the password at deployment time; never commit it.

### Development / proof-of-concept option

The published `litellm-helm` chart can deploy a standalone PostgreSQL subchart. This is convenient for testing but should not be treated as the default production HA database design.

For a serious AI Factory, prefer a separately managed PostgreSQL service with backups, monitoring, encryption, and tested restore procedures.

## 7. Optional Redis

LiteLLM can use Redis as a coordination store for cross-Pod rate limits, spend tracking, and distributed locking.

For one gateway replica Redis is optional.

For multiple gateway replicas it is strongly recommended when those coordinated behaviors matter.

The chart can deploy a bundled Redis subchart with:

```yaml
redis:
  enabled: true
  coordination:
    enabled: true
```

For production, prefer a separately managed HA Redis/Valkey service when possible.

## 8. Confirm the vLLM service

The following guide assumes an internal OpenAI-compatible vLLM endpoint such as:

```text
http://vllm.ai-inference.svc.cluster.local:8000/v1
```

The exact Service name, namespace, and port depend on the inference deployment.

Test it from inside the cluster before adding the gateway:

```bash
kubectl -n llm-gateway run curl-test \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl \
  -- \
  curl -sS http://vllm.ai-inference.svc.cluster.local:8000/v1/models
```

If vLLM requires an API key, include the Authorization header.

Do not continue with gateway troubleshooting until the backend model API works directly.

## 9. Production Helm values

Create a local file such as `/tmp/litellm-values.yaml`. Do not commit credentials into it.

The example below assumes:

- chart `1.100.1`;
- existing PostgreSQL;
- two LiteLLM replicas;
- Traefik ingress;
- cert-manager TLS;
- one internal vLLM model backend;
- optional Redis disabled initially;
- Helm is responsible for database migration hooks.

```yaml
replicaCount: 2

image:
  repository: ghcr.io/berriai/litellm
  tag: "1.100.1"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 4000

masterkeySecretName: litellm-master-key
masterkeySecretKey: master-key

environmentSecrets:
  - litellm-model-secrets

proxyConfigMap:
  create: true

proxy_config:
  model_list:
    - model_name: local-llm
      litellm_params:
        model: openai/<vllm-served-model-name>
        api_base: http://vllm.ai-inference.svc.cluster.local:8000/v1
        api_key: os.environ/VLLM_API_KEY

  general_settings:
    master_key: os.environ/PROXY_MASTER_KEY
    enable_drain_endpoint: true

resources:
  requests:
    cpu: "1"
    memory: 4Gi
  limits:
    cpu: "2"
    memory: 4Gi

autoscaling:
  enabled: false

pdb:
  enabled: true
  minAvailable: 1

strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1

terminationGracePeriodSeconds: 90

db:
  useExisting: true
  deployStandalone: false
  endpoint: <postgres-hostname>
  database: litellm
  secret:
    name: litellm-db
    usernameKey: username
    passwordKey: password

redis:
  enabled: false

migrationJob:
  enabled: true
  activeDeadlineSeconds: 1800
  hooks:
    argocd:
      enabled: false
    helm:
      enabled: true

ingress:
  enabled: true
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: <cluster-issuer-name>
  hosts:
    - host: llm.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: llm-gateway-tls
      hosts:
        - llm.example.com
```

Replace:

```text
<vllm-served-model-name>
<postgres-hostname>
<cluster-issuer-name>
llm.example.com
```

with real environment values.

### Model alias behavior

Applications call the gateway using the LiteLLM alias:

```text
local-llm
```

LiteLLM maps that alias to the real vLLM-served model name and backend URL. This prevents application code from depending on a specific Kubernetes Service or model deployment name.

## 10. Install with Helm

Run a dry render first:

```bash
helm template litellm \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${LITELLM_CHART_VERSION}" \
  --namespace llm-gateway \
  -f /tmp/litellm-values.yaml \
  > /tmp/litellm-rendered.yaml
```

Then install:

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

Check release status:

```bash
helm -n llm-gateway status litellm
helm -n llm-gateway list
```

## 11. Validate Kubernetes resources

```bash
kubectl -n llm-gateway get pods
kubectl -n llm-gateway get svc
kubectl -n llm-gateway get ingress
kubectl -n llm-gateway get jobs
```

Inspect failures:

```bash
kubectl -n llm-gateway get events --sort-by=.lastTimestamp
kubectl -n llm-gateway describe pod <pod-name>
kubectl -n llm-gateway logs <pod-name>
```

The migration Job must complete successfully before considering the deployment healthy.

## 12. Health checks

The chart exposes health endpoints used by its probes, including:

```text
/health/liveliness
/health/readiness
```

Port-forward for a private test:

```bash
kubectl -n llm-gateway port-forward svc/litellm 4000:4000
```

Then:

```bash
curl -sS http://127.0.0.1:4000/health/liveliness
curl -sS http://127.0.0.1:4000/health/readiness
```

The actual Service name can vary with chart/release naming. Confirm with `kubectl -n llm-gateway get svc`.

## 13. Test an inference request

With the port-forward active:

```bash
curl -sS http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local-llm",
    "messages": [
      {"role": "user", "content": "Explain Kubernetes inference in two sentences."}
    ],
    "stream": false
  }'
```

The request path is now:

```text
curl / application
        |
        v
LiteLLM
        |
        v
vLLM Kubernetes Service
        |
        v
vLLM Pod
        |
        v
NVIDIA GPU
        |
        v
response
```

## 14. Public TLS endpoint

After DNS points to the Traefik entry point and cert-manager has issued the certificate:

```bash
curl -sS https://llm.example.com/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local-llm",
    "messages": [
      {"role": "user", "content": "Hello from the AI Factory"}
    ]
  }'
```

Do not expose the gateway publicly without authentication and TLS.

## 15. Multiple models

Add additional entries to `proxy_config.model_list`:

```yaml
proxy_config:
  model_list:
    - model_name: qwen
      litellm_params:
        model: openai/<qwen-served-model-name>
        api_base: http://qwen-vllm.ai-inference.svc.cluster.local:8000/v1
        api_key: os.environ/VLLM_API_KEY

    - model_name: llama
      litellm_params:
        model: openai/<llama-served-model-name>
        api_base: http://llama-vllm.ai-inference.svc.cluster.local:8000/v1
        api_key: os.environ/VLLM_API_KEY
```

Applications now use stable aliases such as `qwen` and `llama` while the platform team can change the underlying model servers independently.

## 16. Local + external provider routing

LiteLLM can also expose local and external models behind the same API.

Conceptually:

```text
model_list:
  local-llm -> internal vLLM
  cloud-a   -> external provider A
  cloud-b   -> external provider B
```

Keep all external provider credentials in Kubernetes Secrets and reference them with `os.environ/...` in LiteLLM configuration.

This enables controlled fallback designs such as:

```text
local model first
      |
      +-- healthy/capacity available -> serve locally
      |
      +-- unavailable/policy allows -> external model
```

Do not add external fallback unless data-governance and cost policy allow requests to leave the cluster.

## 17. High availability

A production gateway should not be a single Pod.

Recommended baseline:

```text
Traefik
   |
   +---------------------+
   |                     |
LiteLLM Pod 1       LiteLLM Pod 2
   |                     |
   +----------+----------+
              |
     PostgreSQL + Redis
              |
              v
      inference backends
```

Use:

- two or more gateway replicas;
- PodDisruptionBudget;
- rolling updates with `maxUnavailable: 0`;
- topology spread/anti-affinity across CPU workers;
- durable PostgreSQL;
- Redis for coordinated multi-replica controls;
- readiness/startup/liveness probes;
- sufficient graceful termination time for streaming requests.

## 18. Autoscaling

The chart supports HPA and KEDA configuration.

Start with fixed replicas until normal load is understood. Then enable autoscaling.

CPU-based HPA example:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 60
```

Do not scale only on memory usage. LLM gateway load is often better represented by request rate, token rate, latency, and queue pressure than by resident memory.

The upstream chart ships only a generic KEDA Prometheus trigger example; scaling on request rate or token rate requires LiteLLM's Prometheus metrics plus a metrics adapter or KEDA that you configure yourself.

## 19. Metrics and observability

Monitor at least:

```text
gateway layer
  request count
  request latency
  error rate
  rate-limit events
  token usage
  backend/provider failures
  retries/fallbacks

inference layer
  time to first token
  inter-token latency
  tokens/sec
  active requests
  queued requests
  KV-cache utilization
  model load state

GPU layer
  utilization
  memory used/free
  temperature
  power
  errors
```

For GPU workers use NVIDIA DCGM Exporter/Prometheus through the GPU platform stack.

The LiteLLM chart has ServiceMonitor/metrics options, but review the exact pinned chart values before enabling them because this area changes across releases.

## 20. Security requirements

### Never commit these values

- LiteLLM master key;
- virtual keys;
- external provider API keys;
- vLLM backend API key;
- PostgreSQL username/password;
- Redis password;
- TLS private keys.

### Recommended controls

- TLS at Traefik.
- LiteLLM authentication for every client.
- NetworkPolicy restricting LiteLLM egress to approved model servers/database/Redis and approved external providers.
- NetworkPolicy restricting direct access to vLLM so normal clients must go through LiteLLM.
- non-root containers where supported by the selected chart/image version;
- dropped Linux capabilities where compatible;
- read-only root filesystem where compatible;
- Pod Security Admission policy;
- Kubernetes RBAC with least privilege;
- secret rotation;
- image and Helm chart pinning;
- container/image signature verification where part of the supply-chain policy;
- audit logging without recording sensitive prompt content unless explicitly required.

## 21. Direct vLLM access vs gateway access

Do not expose both to ordinary clients.

Preferred production pattern:

```text
client
  |
  v
LiteLLM
  |
  v
private vLLM Service
```

The vLLM Service should normally be `ClusterIP` and reachable only from trusted namespaces/workloads.

This gives one security and policy enforcement point.

## 22. Relationship to Traefik

Traefik remains the general Kubernetes north-south entry point.

LiteLLM does not replace it.

```text
Internet / internal client
          |
          v
       Traefik
  TLS / hostname routing
          |
          v
       LiteLLM
 AI auth/model policy
          |
          v
        vLLM
 model inference/GPU
```

Traefik answers **where should this HTTP request enter the cluster?**

LiteLLM answers **which AI model/provider should handle this authenticated AI request and under what policy?**

## 23. Relationship to Gateway API Inference Extension

Gateway API Inference Extension is an official Kubernetes project for optimized routing to self-hosted generative-model servers.

Its stable `InferencePool` API represents a pool of model-server Pods. An inference-aware gateway can use model-server metrics such as queue pressure and KV-cache state to select a better endpoint than normal round-robin load balancing.

That is useful later when one logical model has several GPU-backed replicas:

```text
LiteLLM
   |
   v
Inference Gateway / InferencePool
   |
   +---------------+---------------+
   |               |               |
vLLM Pod 1     vLLM Pod 2     vLLM Pod 3
GPU             GPU             GPU
```

### Do not add it on day one

The Inference Extension project defines APIs and conformance, but it does not provide one universal default gateway controller. A conformant implementation must be selected, such as one listed by the project.

Therefore the recommended progression is:

```text
Stage 1
Traefik -> LiteLLM -> one vLLM Service

Stage 2
Traefik -> LiteLLM -> several model Services

Stage 3
Traefik -> LiteLLM -> inference-aware Gateway/InferencePool -> many replicas of one model
```

Do not introduce the extra control plane until model replica count and GPU utilization justify it.

## 24. Gateway API versions

The Kubernetes Gateway API project currently documents `v1.6.1` installation bundles, and `v1.6.2` was released on 2026-09-03. Gateway API supports several recent Kubernetes minors through CRDs, so Kubernetes 1.36 does not prevent use of current Gateway API features.

This repository does **not** require Gateway API/Inferences Extension for the first LiteLLM deployment.

If adding it later, pin its API/controller versions separately from Kubernetes and test conformance with the chosen implementation.

## 25. Upgrade procedure

Never upgrade the chart and application blindly.

### Inspect the target release

```bash
export NEW_LITELLM_VERSION=<stable-version>

helm show chart \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${NEW_LITELLM_VERSION}"

helm show values \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${NEW_LITELLM_VERSION}" \
  > /tmp/litellm-values-new.yaml
```

Compare the old and new chart values before upgrading.

### Render first

```bash
helm template litellm \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${NEW_LITELLM_VERSION}" \
  --namespace llm-gateway \
  -f /tmp/litellm-values.yaml \
  > /tmp/litellm-rendered-new.yaml
```

### Upgrade

```bash
helm upgrade litellm \
  oci://ghcr.io/berriai/litellm-helm \
  --version "${NEW_LITELLM_VERSION}" \
  --namespace llm-gateway \
  -f /tmp/litellm-values.yaml \
  --wait \
  --timeout 15m
```

Because LiteLLM uses database migrations, back up PostgreSQL and review migration behavior before a major or potentially breaking upgrade.

## 26. Rollback

List revisions:

```bash
helm -n llm-gateway history litellm
```

Rollback Helm resources:

```bash
helm -n llm-gateway rollback litellm <revision> --wait
```

A Helm rollback does not automatically undo an incompatible database migration. Treat database backup/restore as part of the rollback design.

## 27. Uninstall

```bash
helm -n llm-gateway uninstall litellm
```

Do not automatically delete PostgreSQL data, Secrets, or certificates until retention requirements are understood.

## 28. Troubleshooting sequence

Use this order:

```text
1. Is the model backend healthy directly?
2. Can LiteLLM namespace resolve/reach the model Service?
3. Are LiteLLM Pods Ready?
4. Did the database migration Job succeed?
5. Can LiteLLM authenticate to PostgreSQL/Redis?
6. Does a port-forwarded LiteLLM request work?
7. Does Traefik route to LiteLLM?
8. Is TLS/DNS correct?
```

Useful commands:

```bash
kubectl -n llm-gateway get all
kubectl -n llm-gateway get events --sort-by=.lastTimestamp
kubectl -n llm-gateway logs deploy/litellm --tail=200
kubectl -n llm-gateway describe deploy litellm
helm -n llm-gateway status litellm
helm -n llm-gateway get values litellm
helm -n llm-gateway get manifest litellm
```

Do not start by restarting Pods. Determine whether the fault is model serving, DNS/networking, Secret/configuration, database migration, or ingress/TLS first.

## 29. Recommended production AI Factory topology

```text
                          clients / applications
                                  |
                                  v
                             DNS + TLS
                                  |
                                  v
                               Traefik
                                  |
                                  v
                        LiteLLM Gateway (CPU)
                         2+ replicas / HPA
                                  |
                +-----------------+-----------------+
                |                                   |
                v                                   v
        PostgreSQL / Redis                  inference services
                                                    |
                          +-------------------------+------------------+
                          |                         |                  |
                          v                         v                  v
                       vLLM                     KServe             KubeRay
                          |                         |                  |
                          +-------------------------+------------------+
                                                    |
                                              GPU workers
                                                    |
                                            physical NVIDIA GPUs
```

For the first production milestone, keep it simpler:

```text
Traefik
   |
LiteLLM
   |
vLLM Service
   |
1 GPU worker
```

Prove reliability and observability before adding additional gateway layers.

## 30. Repository recommendation

For this project, the implementation order should be:

1. Build the RKE2 / Kubernetes 1.36 AI Factory profile, or evaluate on the current K3s `v1.36.4+k3s1` repository cluster.
2. Add NVIDIA GPU integration on dedicated workers.
3. Deploy one vLLM model and validate direct inference.
4. Install LiteLLM via the pinned Helm chart.
5. Route application traffic through LiteLLM.
6. Add durable PostgreSQL and Redis for the production gateway profile.
7. Add Prometheus/Grafana and request/token/GPU observability.
8. Add more models and LiteLLM routing/fallback policies.
9. Add Gateway API Inference Extension only when multiple replicas of the same model need inference-aware GPU routing.

This keeps the first deployment understandable while leaving a clean path to a larger AI Factory.

## Official references

- LiteLLM documentation: <https://docs.litellm.ai/>
- LiteLLM GitHub repository: <https://github.com/BerriAI/litellm>
- LiteLLM official Helm OCI package: <https://github.com/BerriAI/litellm/pkgs/container/litellm-helm>
- LiteLLM Helm values: <https://github.com/BerriAI/litellm/tree/main/helm>
- vLLM OpenAI-compatible server: <https://docs.vllm.ai/en/latest/serving/online_serving/openai_compatible_server/>
- vLLM Kubernetes deployment: <https://docs.vllm.ai/en/latest/deployment/k8s/>
- vLLM Production Stack: <https://docs.vllm.ai/projects/production-stack/en/latest/>
- Kubernetes Gateway API: <https://gateway-api.sigs.k8s.io/>
- Gateway API Inference Extension: <https://gateway-api-inference-extension.sigs.k8s.io/>
- Gateway API Inference Extension implementations: <https://gateway-api-inference-extension.sigs.k8s.io/implementations/gateways/>
- Gateway API InferencePool: <https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepool/>
