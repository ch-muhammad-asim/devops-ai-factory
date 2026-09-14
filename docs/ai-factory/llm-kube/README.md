# LLMKube for the AI Factory

> **Research review:** 2026-09-13. This guide is based on the current LLMKube documentation and upstream Helm chart. The target production AI Factory baseline remains Ubuntu 24.04 LTS + RKE2 / Kubernetes 1.36.x + containerd + NVIDIA GPU Operator. The repository as committed today runs K3s `v1.36.4+k3s1` (Kubernetes 1.36) on a single Ubuntu 26.04 LTS `t3.medium` EC2 node with no GPU; see [`../kubernetes-distribution-recommendation.md`](../kubernetes-distribution-recommendation.md) for why the production profile differs.

## Decision

**LLMKube is useful, but it is not required to build this AI Factory.**

The core AI Factory can already serve models with:

```text
Kubernetes 1.36 (RKE2 profile or current K3s)
        |
NVIDIA GPU Operator
        |
vLLM / KServe / KubeRay
        |
LiteLLM Gateway
        |
applications
```

LLMKube becomes valuable when the platform team wants a Kubernetes-native operator dedicated to self-hosted LLM inference: declarative model lifecycle, model caching, runtime selection, GPU scheduling, health checks, metrics, autoscaling and OpenAI-compatible endpoints from purpose-built CRDs.

For this repository, treat LLMKube as an **optional inference-platform layer**, not a mandatory dependency.

Recommended architecture if LLMKube is adopted:

```text
applications
     |
     v
Traefik + TLS
     |
     v
LiteLLM Gateway
     |
     v
LLMKube-managed InferenceService
     |
     +---------------------------+
     |             |             |
    vLLM        llama.cpp       TGI / other runtime
     |             |             |
     +-------------+-------------+
                   |
          Kubernetes GPU worker
                   |
          NVIDIA GPU Operator
                   |
          physical NVIDIA GPU
```

The LLMKube controller itself is a CPU workload. The GPU is consumed by the inference runtime pods it creates.

---

## What LLMKube is

LLMKube is an Apache-2.0 Kubernetes operator for self-hosted LLM inference.

Its primary abstraction is Kubernetes CRDs rather than shell scripts or standalone model runners:

```text
Model
  -> describes the model artifact and hardware intent

InferenceService
  -> describes how the model should be served
  -> runtime, replicas, resources, GPU count, scheduling, endpoint
```

The operator reconciles those resources into model downloads/caches, pods, Services, health checks and runtime configuration.

Current upstream documentation describes support for multiple inference runtimes, including vLLM, llama.cpp, SGLang, TGI and generic/custom runtime paths. Its `hardware.accelerator` field covers NVIDIA (`cuda`), AMD (`rocm`), Intel, Vulkan, Apple Silicon (`metal`) and CPU deployment paths.

Official project:

- <https://llmkube.com/>
- <https://llmkube.com/docs>
- <https://github.com/defilantech/LLMKube>

---

## Current version pin

The upstream Helm chart on `main` currently declares:

```text
chart version: 0.9.25
appVersion:    0.9.25
```

This repository therefore documents **LLMKube 0.9.25** as the current production evaluation pin.

Do not use an unpinned chart in production. Before upgrading, re-check the upstream chart and release notes.

Verify locally:

```bash
helm repo add llmkube https://defilantech.github.io/LLMKube
helm repo update
helm search repo llmkube/llmkube --versions | head
helm show chart llmkube/llmkube --version 0.9.25
```

---

## Do we really need LLMKube?

### No, not for the first AI Factory milestone

The minimum production inference stack can remain:

```text
Ubuntu 24.04 (production profile) or Ubuntu 26.04 (current repository)
+
RKE2 or K3s / Kubernetes 1.36
+
NVIDIA GPU Operator
+
vLLM
+
Kubernetes Service
+
LiteLLM Gateway
+
Traefik
```

That is enough to load a model on a physical NVIDIA GPU and expose an inference API.

### Add LLMKube when these problems appear

LLMKube becomes attractive when we need several of the following at the same time:

- many self-hosted models;
- more than one inference runtime;
- repeatable model download and cache management;
- declarative model lifecycle through CRDs;
- multi-GPU placement/sharding patterns;
- model-serving health/status represented in Kubernetes;
- runtime-aware autoscaling;
- Prometheus/Grafana integration around inference;
- GitOps-managed model definitions;
- heterogeneous accelerator fleets;
- a Kubernetes-native abstraction above raw vLLM Deployments.

### Avoid duplicate control planes

Do not deploy LLMKube and KServe to manage the **same model deployment** unless there is a deliberate ownership boundary.

Choose one primary model-serving control plane per workload:

```text
Option A
LLMKube -> vLLM/llama.cpp/TGI

Option B
KServe -> vLLM/serving runtime

Option C
plain Kubernetes Deployment -> vLLM
```

LiteLLM is different: it is an API/gateway layer and can sit in front of any of those choices.

LLMKube also has routing capabilities such as `ModelRouter`. If LiteLLM is already the central LLM Gateway, do not introduce a second routing layer unless a specific LLMKube policy-routing feature is required.

---

## Fit for this repository

Our target production AI Factory direction is:

```text
Ubuntu Server 24.04 LTS
RKE2 / Kubernetes 1.36.x
containerd
3 x CPU control-plane / etcd servers
CPU worker pool
GPU worker pool
NVIDIA GPU Operator
Traefik
cert-manager
Argo CD
LiteLLM Gateway
```

The repository as committed today is smaller: one Ubuntu 26.04 LTS `t3.medium` EC2 node running K3s `v1.36.4+k3s1` with Traefik, cert-manager and Argo CD, and no GPU node. Treat the block above as the target topology, not the current one.

LLMKube's current quick-start documentation requires Kubernetes `1.27+`, Helm `3.0+`, `kubectl`, and cluster-admin permissions for CRD installation. Kubernetes 1.36 therefore satisfies its documented Kubernetes minimum.

Use LLMKube on the **worker side** of this architecture. Do not schedule inference workloads on control-plane/etcd nodes.

---

## Requirements

### Kubernetes

```text
Recommended here: RKE2 / Kubernetes 1.36.x (current repository: K3s v1.36.4+k3s1)
Upstream LLMKube documented minimum: Kubernetes 1.27+
```

Required operator access:

```bash
kubectl auth can-i create customresourcedefinitions.apiextensions.k8s.io
```

Expected result:

```text
yes
```

### Helm

Use Helm 3:

```bash
helm version
```

### kubectl

Confirm the current cluster before installation:

```bash
kubectl config current-context
kubectl get nodes -o wide
```

### Storage

Model weights are large. LLMKube supports model caching and model sources such as HTTP/Hugging Face, object storage and PVC-backed content.

For production, provide a StorageClass suitable for the model size and access pattern:

```bash
kubectl get storageclass
```

Do not assume the control-plane root disk is adequate for model storage.

### Network access

For connected deployments, worker nodes/pods need access to the model source and required image registries.

For restricted or air-gapped environments, mirror runtime/operator images and stage model artifacts through approved object storage or PVCs.

### NVIDIA GPU requirements

For NVIDIA inference workers, the expected path is:

```text
physical NVIDIA GPU
        |
Ubuntu 24.04 / 26.04 GPU worker
        |
NVIDIA driver/runtime integration
        |
NVIDIA GPU Operator
        |
Kubernetes exposes nvidia.com/gpu
        |
LLMKube InferenceService
        |
vLLM / llama.cpp / other runtime
```

Verify GPU visibility before deploying LLMKube workloads:

```bash
kubectl get nodes
kubectl describe node <gpu-node> | grep -A5 -B2 nvidia.com/gpu
```

A GPU node should report allocatable GPU resources such as:

```text
nvidia.com/gpu: 1
```

LLMKube does **not** replace NVIDIA GPU Operator. LLMKube orchestrates inference workloads; GPU Operator manages the NVIDIA software/device integration that exposes GPUs to Kubernetes.

### cert-manager

This repository already uses cert-manager.

LLMKube's current Helm chart can use cert-manager for its validating webhook certificate. That path is particularly useful with Argo CD because it avoids Helm `lookup` dependence for the self-generated webhook certificate.

When `webhook.certManager.enabled=true` and no external issuer is specified, the chart creates its own namespaced self-signed Issuer and Certificate.

---

## Helm installation

### 1. Add the repository

```bash
helm repo add llmkube https://defilantech.github.io/LLMKube
helm repo update
```

Inspect the chart before deployment:

```bash
helm search repo llmkube/llmkube --versions | head
helm show chart llmkube/llmkube --version 0.9.25
helm show values llmkube/llmkube --version 0.9.25 > /tmp/llmkube-values-0.9.25.yaml
```

### 2. Create a production values file

Example baseline for this repository:

```yaml
controllerManager:
  replicaCount: 1
  leaderElection:
    enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      memory: 2Gi

webhook:
  enabled: true
  failurePolicy: Fail
  certManager:
    enabled: true

crds:
  install: true
  keep: true

metrics:
  enabled: true
  secure: true

prometheus:
  serviceMonitor:
    enabled: false
  prometheusRule:
    enabled: false

grafana:
  dashboards:
    enabled: false
```

Save it as, for example:

```text
llmkube-values.yaml
```

Notes:

- enable `prometheus.serviceMonitor` only when Prometheus Operator / kube-prometheus-stack is installed;
- enable `prometheus.prometheusRule` only when the matching CRDs exist;
- enable Grafana dashboards after the monitoring stack is ready;
- keep the controller on CPU workers;
- pin image digests later for stronger production immutability.

### 3. Render before applying

```bash
helm template llmkube llmkube/llmkube \
  --namespace llmkube-system \
  --version 0.9.25 \
  -f llmkube-values.yaml > /tmp/llmkube-rendered.yaml
```

Check the output for unexpected objects or namespaces before installation.

### 4. Install / upgrade

```bash
helm upgrade --install llmkube llmkube/llmkube \
  --namespace llmkube-system \
  --create-namespace \
  --version 0.9.25 \
  -f llmkube-values.yaml \
  --wait \
  --timeout 10m
```

### 5. Verify

```bash
helm list -n llmkube-system
kubectl get pods -n llmkube-system
kubectl get deploy -n llmkube-system
kubectl get svc -n llmkube-system
kubectl get crd | grep llmkube
```

Check the controller:

```bash
kubectl logs -n llmkube-system deploy/llmkube-controller-manager --tail=200
```

The exact Deployment name can vary with Helm release naming, so use this if needed:

```bash
kubectl get deploy -n llmkube-system
```

---

## Optional LLMKube CLI

The CLI is convenient but not required. Kubernetes resources can be managed directly with `kubectl` and Argo CD.

macOS:

```bash
brew tap defilantech/tap
brew install llmkube
llmkube version
```

The CLI can deploy catalog models quickly:

```bash
llmkube catalog list
llmkube catalog info llama-3.1-8b
llmkube deploy llama-3.1-8b --gpu --runtime vllm
```

For production, prefer Git-managed CRDs through Argo CD rather than relying only on imperative CLI commands.

---

## First model: simple GPU example

A small declarative example can use the core `Model` and `InferenceService` CRDs.

```yaml
apiVersion: inference.llmkube.dev/v1alpha1
kind: Model
metadata:
  name: phi-3-mini
spec:
  source: https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf
  format: gguf
  quantization: Q4_K_M
  hardware:
    accelerator: cuda
    gpu:
      enabled: true
      count: 1
  resources:
    cpu: "2"
    memory: 4Gi
---
apiVersion: inference.llmkube.dev/v1alpha1
kind: InferenceService
metadata:
  name: phi-3-mini
spec:
  modelRef: phi-3-mini
  replicas: 1
  resources:
    gpu: 1
    cpu: "2"
    memory: 4Gi
```

Apply:

```bash
kubectl apply -f model.yaml
```

Observe:

```bash
kubectl get models
kubectl get inferenceservices
kubectl describe model phi-3-mini
kubectl describe inferenceservice phi-3-mini
kubectl get pods -o wide
```

For the production AI Factory, vLLM/SafeTensors models are likely more relevant than a small GGUF example. This first manifest is intentionally simple so the operator, model cache and GPU scheduling path can be validated before deploying a larger model.

---

## Worked example: Gemma 3 1B on the current CPU-only node

This example runs end to end on the repository as committed today: one Ubuntu 26.04 LTS `t3.medium` (2 vCPU, 4 GiB RAM) running K3s `v1.36.4+k3s1`, no GPU. It uses the smallest instruction-tuned Gemma release in GGUF form on the llama.cpp runtime, which is LLMKube's default. Everything below was checked against the v0.9.25 CRDs and the Hugging Face repositories on 2026-09-13.

### What Hugging Face is

[Hugging Face](https://huggingface.co) is the public registry where most open-weight models are published. Think of it as GitHub for model files:

- A **model repository** has an owner and a name, for example `google/gemma-3-1b-it`. It holds the weights, a `config.json`, tokenizer files and a model card describing the license and intended use.
- Files are fetched over HTTPS from `https://huggingface.co/<owner>/<repo>/resolve/main/<file>`. LLMKube's `hf://` source scheme is shorthand for exactly that URL.
- **Gated repositories** require you to be logged in and to accept the publisher's terms once, in the browser, before any download works. Access is granted per user, not per organization.
- A **User Access Token** authenticates scripts and clusters instead of your password. Create one under Settings, Access Tokens. Use a `read` token, or better a `fine-grained` token scoped to just the repository you need, and never commit it to Git.

### Which Gemma files to use

Gemma weights come in two shapes:

| Repository | Format | Gated | Size | Use with |
|---|---|---|---|---|
| `google/gemma-3-1b-it` | SafeTensors (original) | Yes, manual acceptance of the Gemma terms | ~2 GB | vLLM, TGI, transformers |
| `ggml-org/gemma-3-1b-it-GGUF` | GGUF, converted by the llama.cpp maintainers | No | Q4_K_M 806 MB, Q8_0 1.07 GB, F16 2.0 GB | llama.cpp |

The GGUF conversion is what runs on a CPU. It is not gated, so no token is needed for the download, but it is still distributed under Google's [Gemma Terms of Use](https://ai.google.dev/gemma/terms), which you accept by using it. `Q4_K_M` is the standard 4-bit quantization: a quarter of the memory of the original for a small quality loss, and the right choice for a 4 GiB node.

The context window is 32K tokens, but every token of context costs KV-cache memory. On this node keep it at 2048.

### Step 1: install LLMKube

Follow the Helm installation section above. K3s ships the `local-path` StorageClass as default, which satisfies the operator's `ReadWriteOnce` model cache. On a fresh install the values file needs nothing storage-specific:

```bash
helm upgrade --install llmkube llmkube/llmkube \
  --namespace llmkube-system \
  --create-namespace \
  --version 0.9.25 \
  -f llmkube-values.yaml \
  --wait --timeout 10m

kubectl get storageclass
kubectl -n llmkube-system get pods
```

### Step 2: create a namespace and, if needed, the token Secret

Models live in their own namespace. The operator creates the shared cache PVC `llmkube-model-cache` there on first use.

```bash
kubectl create namespace ai-models
```

The GGUF repository is public, so this step is optional for the example. It becomes required the moment you point at a gated or private repository such as `google/gemma-3-1b-it`. LLMKube reads the token from a Secret key named `HF_TOKEN` and sends it only to `huggingface.co`, dropping it on any redirect to a CDN:

```bash
read -rs HF_TOKEN
kubectl -n ai-models create secret generic hf-token --from-literal=HF_TOKEN="$HF_TOKEN"
unset HF_TOKEN
```

Before that works for a gated repository, open its page in the browser while logged in and click **Agree and send request to access repo**. For `google/gemma-3-1b-it` approval is manual and can take a while.

### Step 3: declare the Model

`gemma-model.yaml`:

```yaml
apiVersion: inference.llmkube.dev/v1alpha1
kind: Model
metadata:
  name: gemma-3-1b-it
  namespace: ai-models
spec:
  # hf://<owner>/<repo>/<file> resolves to https://huggingface.co/<owner>/<repo>/resolve/main/<file>
  source: hf://ggml-org/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf
  format: gguf
  quantization: Q4_K_M

  # Download into the namespace's shared cache now, before any InferenceService exists.
  prefetch: true

  # Uncomment for a gated or private repository. The Secret must exist first.
  # sourceSecretRef:
  #   name: hf-token

  hardware:
    accelerator: cpu

  resources:
    cpu: "1"
    memory: 2Gi
```

Apply it and watch the download Job:

```bash
kubectl apply -f gemma-model.yaml
kubectl -n ai-models get model gemma-3-1b-it -w
kubectl -n ai-models logs job/gemma-3-1b-it-prefetch -f
kubectl -n ai-models get pvc
```

`status.phase` moves from `Downloading` to `Ready`, and `status.cacheKey` records the hash the file is stored under. The 806 MB pull takes a minute or two on the EC2 node. Delete and recreate the Model or its InferenceService afterwards and nothing is downloaded again.

### Step 4: declare the InferenceService

`gemma-service.yaml`:

```yaml
apiVersion: inference.llmkube.dev/v1alpha1
kind: InferenceService
metadata:
  name: gemma-3-1b-it
  namespace: ai-models
spec:
  modelRef: gemma-3-1b-it
  runtime: llamacpp
  replicas: 1

  # Sized for a 4 GiB node shared with K3s, Traefik, cert-manager and Argo CD.
  contextSize: 2048
  parallelSlots: 1
  noWarmup: true

  endpoint:
    port: 8080
    path: /v1/chat/completions
    type: ClusterIP

  resources:
    gpu: 0
    cpu: "1"
    memory: 2Gi
```

`parallelSlots: 1` limits llama.cpp to one request at a time, which keeps KV-cache memory predictable. Raise `contextSize` and `parallelSlots` together with `resources.memory` on a bigger node.

```bash
kubectl apply -f gemma-service.yaml
kubectl -n ai-models get inferenceservice gemma-3-1b-it -w
kubectl -n ai-models get pods -o wide
kubectl -n ai-models logs deploy/gemma-3-1b-it -f
```

The pod starts from the cached file, so it should be `Ready` within a minute once the image `ghcr.io/ggml-org/llama.cpp:server` is pulled.

### Step 5: send a request

llama.cpp exposes an OpenAI-compatible API. Port-forward the Service and ask it something:

```bash
kubectl -n ai-models port-forward svc/gemma-3-1b-it 8080:8080
```

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma-3-1b-it",
    "messages": [{"role": "user", "content": "In two sentences, what is Kubernetes?"}],
    "max_tokens": 120
  }'
```

Expect a few tokens per second on two vCPUs. That is enough to prove the operator, the cache, the Hugging Face download path and the OpenAI-compatible surface before any GPU exists. The same Service is what a LiteLLM or AgentGateway backend would point at.

### Step 6: clean up

```bash
kubectl -n ai-models delete inferenceservice gemma-3-1b-it
kubectl -n ai-models delete model gemma-3-1b-it
kubectl -n ai-models delete secret hf-token
kubectl delete namespace ai-models
```

Deleting the namespace also removes the cache PVC and the downloaded file.

### Fitting on the t3.medium

The platform components already use roughly half of the node's 4 GiB. If the inference pod stays `Pending` with an insufficient-memory event, or is OOM-killed, check `kubectl top node` and either lower `contextSize` to 1024 or move the node to `t3.large` by changing `instance_type` in `infrastructure/live/_common/ec2.hcl`. That change replaces the EC2 instance, so clear termination protection first as the platform README describes.

### Moving to the original weights and a GPU

When a GPU worker exists, the same pattern serves the gated SafeTensors release through vLLM: set `source: google/gemma-3-1b-it` on the Model, keep `sourceSecretRef` pointing at the `HF_TOKEN` Secret so vLLM can download at start-up, use `runtime: vllm` with `skipModelInit: true` on the InferenceService, and request `resources.gpu: 1`. The next section covers that path.

---

## vLLM path

LLMKube can manage vLLM as the runtime rather than us hand-writing every vLLM Deployment.

The high-level path becomes:

```text
Model CR
      |
InferenceService(runtime=vllm)
      |
LLMKube controller
      |
vLLM inference pod
      |
nvidia.com/gpu
      |
GPU worker
```

A simplified vLLM `InferenceService` example, using only fields present in the v0.9.25 CRD, looks like this (the upstream multi-node guide uses a different `multiNode`-based shape):

```yaml
apiVersion: inference.llmkube.dev/v1alpha1
kind: InferenceService
metadata:
  name: my-vllm-service
spec:
  modelRef: my-model
  runtime: vllm
  replicas: 1
  resources:
    gpu: 1
    cpu: "8"
    memory: 32Gi
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  vllmConfig:
    tensorParallelSize: 1
    gpuMemoryUtilization: 0.90
```

The exact model, image, memory, tensor-parallel size, context length and GPU memory utilization must be sized from the selected model and GPU hardware. Do not copy resource values blindly between models.

---

## Test the inference API

After the `InferenceService` is ready, inspect the generated Service:

```bash
kubectl get svc
kubectl get inferenceservices
```

For a simple local test:

```bash
kubectl port-forward svc/<inference-service> 8080:8080
```

Then call the OpenAI-compatible endpoint:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {"role": "user", "content": "Explain Kubernetes in one sentence"}
    ],
    "max_tokens": 100
  }'
```

Do not expose every generated inference Service directly to the Internet. In the target architecture, applications should normally enter through Traefik/LiteLLM and reach the internal inference Service over cluster networking.

---

## Integration with LiteLLM Gateway

LLMKube and LiteLLM solve different problems and can complement each other.

```text
LiteLLM
  -> API authentication
  -> model aliases
  -> budgets / quotas
  -> provider routing
  -> one stable application API

LLMKube
  -> model lifecycle
  -> runtime lifecycle
  -> model cache
  -> GPU scheduling
  -> inference pod health
  -> inference metrics
```

Recommended relationship:

```text
client
  |
Traefik
  |
LiteLLM
  |
ClusterIP Service created for an LLMKube InferenceService
  |
vLLM pod
  |
GPU
```

If LiteLLM is our gateway, keep LLMKube `ModelRouter` out of the first deployment unless we need its specific policy-aware hybrid-routing behavior. Two overlapping routing layers increase debugging complexity.

See:

[`../llm-gateway/README.md`](../llm-gateway/README.md)

---

## Argo CD / GitOps

LLMKube is a good fit for GitOps because its model-serving configuration is represented as Kubernetes CRDs.

Recommended ownership:

```text
Helm release
  -> installs LLMKube operator + CRDs

Argo CD
  -> manages Model CRs
  -> manages InferenceService CRs
  -> manages namespace-level policy/configuration
```

Install order matters:

```text
cert-manager
   |
LLMKube operator + CRDs
   |
Model CRs
   |
InferenceService CRs
   |
LiteLLM backend configuration
```

Do not allow Argo CD to apply `Model` or `InferenceService` resources before the corresponding CRDs exist.

---

## Monitoring

LLMKube exposes metrics and its Helm chart includes optional Prometheus and Grafana integration.

For our AI Factory, the eventual observability path can be:

```text
Prometheus
   +-- Kubernetes metrics
   +-- LLMKube controller metrics
   +-- inference runtime metrics
   +-- NVIDIA DCGM metrics

Grafana
   +-- model latency
   +-- request queue depth
   +-- TTFT
   +-- throughput/tokens
   +-- GPU utilization
   +-- GPU memory
   +-- GPU temperature/power
```

If using inference-metric HPA, current LLMKube documentation notes that Prometheus Adapter is needed to expose the custom runtime metrics to Kubernetes HPA.

Do not enable both annotation scraping and PodMonitor/ServiceMonitor for the same targets unless the monitoring design intentionally handles duplicate discovery.

---

## Scaling

LLMKube supports Kubernetes HPA-oriented inference scaling and current documentation provides runtime-specific scaling signals.

Remember that ordinary replica autoscaling and GPU-node autoscaling are different:

```text
InferenceService / HPA
   -> changes inference pod replica count

node autoscaler / Karpenter / infrastructure automation
   -> changes available GPU node capacity
```

For on-prem physical GPUs, node count is usually fixed. HPA can only scale up to the number of GPUs actually available.

For AWS GPU workers, a future profile could combine LLMKube with Karpenter or infrastructure-driven GPU capacity, but that is optional and should be introduced only after a stable single-GPU inference path exists.

---

## Multi-GPU and multi-node inference

LLMKube supports multi-GPU use cases and its current documentation includes multi-node inference with vLLM.

Do not start the AI Factory with distributed inference unless the chosen model cannot fit or perform acceptably on one GPU node.

A sensible progression is:

```text
1 GPU / 1 model
      |
1 node / multiple GPUs
      |
tensor parallelism
      |
multi-node serving
      |
RDMA / high-speed fabric when required
```

Distributed inference introduces NCCL/network topology, high-bandwidth networking, model-cache distribution and failure-domain complexity.

---

## Security guidance

Use normal Kubernetes security controls around LLMKube:

```text
RBAC
NetworkPolicy
namespaces
Pod Security / securityContext
Secrets
private registry credentials
model repository credentials
TLS at the gateway
resource quotas
pinned chart/runtime versions
image digests for production
```

Do not place Hugging Face tokens, object-store credentials, model API keys or registry credentials in Git.

The LLMKube chart defaults to a non-root controller security context and drops Linux capabilities for the manager container. Keep those protections unless a documented runtime requirement says otherwise.

---

## Upgrade procedure

Before upgrading:

```bash
helm repo update
helm search repo llmkube/llmkube --versions | head -20
helm get values llmkube -n llmkube-system > /tmp/llmkube-current-values.yaml
```

Render the target version:

```bash
helm template llmkube llmkube/llmkube \
  -n llmkube-system \
  --version <target-version> \
  -f llmkube-values.yaml > /tmp/llmkube-target.yaml
```

Then upgrade:

```bash
helm upgrade llmkube llmkube/llmkube \
  -n llmkube-system \
  --version <target-version> \
  -f llmkube-values.yaml \
  --wait \
  --timeout 10m
```

Validate controller logs and at least one inference workload before upgrading production model fleets.

---

## Rollback

```bash
helm history llmkube -n llmkube-system
helm rollback llmkube <revision> -n llmkube-system --wait
```

CRDs are intentionally kept by default. A Helm rollback does not automatically undo every CRD schema migration, so read upstream upgrade notes before moving between versions that change CRDs.

---

## Uninstall

Remove the Helm release:

```bash
helm uninstall llmkube -n llmkube-system
```

The chart keeps CRDs by default to avoid deleting model-serving custom resources accidentally.

Only remove CRDs after confirming no workloads depend on them:

```bash
kubectl get crd | grep llmkube
```

Do not blindly delete CRDs in production because deleting a CRD also deletes the custom resources stored under it.

---

## Recommended rollout for this AI Factory

```text
Phase 1
Kubernetes 1.36 (RKE2 or K3s) + GPU Operator + one vLLM Deployment
        |
        v
prove host GPU inference

Phase 2
LiteLLM Gateway
        |
        v
one stable application API

Phase 3 - optional
LLMKube 0.9.25 evaluation
        |
        v
move one non-critical model from raw Deployment to Model + InferenceService

Phase 4
Prometheus / Grafana / DCGM
        |
        v
validate inference SLOs and GPU metrics

Phase 5
adopt LLMKube broadly only if it reduces operational complexity
```

### Final recommendation

For this repository:

> **Do not make LLMKube a mandatory dependency of the AI Factory. Evaluate it as the Kubernetes-native model-serving operator once the basic vLLM + GPU + LiteLLM path is proven.**

If the project eventually needs many self-hosted models, multiple runtimes, model caching, GPU-aware scheduling and declarative inference lifecycle, LLMKube can become the primary serving-control layer and replace hand-written vLLM Deployments.

If the project remains a small number of stable vLLM services, plain Kubernetes/KServe may be simpler and LLMKube would add another operator without enough benefit.

---

## Official references

- LLMKube home: <https://llmkube.com/>
- LLMKube docs: <https://llmkube.com/docs>
- LLMKube quick start: <https://llmkube.com/docs/getting-started>
- LLMKube comparison: <https://llmkube.com/docs/concepts/comparison>
- LLMKube features: <https://llmkube.com/features>
- LLMKube FAQ: <https://llmkube.com/faq>
- LLMKube GitHub: <https://github.com/defilantech/LLMKube>
- LLMKube Helm chart source: <https://github.com/defilantech/LLMKube/tree/main/charts/llmkube>
- Multi-node inference: <https://llmkube.com/docs/guides/multi-node-inference>
- Metrics-driven autoscaling: <https://llmkube.com/docs/guides/metrics-driven-autoscaling>
