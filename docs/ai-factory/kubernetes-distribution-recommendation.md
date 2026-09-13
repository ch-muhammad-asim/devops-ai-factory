# Kubernetes distribution recommendation for an AI Factory

> **Research review:** 2026-09-13. Checked against current NVIDIA AI Enterprise 8.2, NVIDIA GPU Operator, NVIDIA Enterprise Reference Architecture, RKE2, KServe, vLLM and Kubernetes 1.36 documentation.

## Recommendation

There is no single Kubernetes distribution that NVIDIA declares to be the universal "AI Factory distribution." NVIDIA validates several Kubernetes platforms, while its own reference architectures commonly use **upstream Kubernetes**.

For this repository's goal — a **self-hosted production AI Factory** — the recommended distribution is **RKE2**.

Recommended production baseline today:

```text
Ubuntu Server 24.04 LTS
        |
        v
RKE2 / Kubernetes 1.36.x
        |
        v
containerd
        |
        +-- NVIDIA GPU Operator
        +-- NVIDIA Network Operator when required
        +-- Kueue or Run:ai
        +-- vLLM / KServe / KubeRay / NIM workloads
        +-- Prometheus / Grafana / DCGM
        +-- Argo CD
```

The reason for preferring Ubuntu 24.04 LTS for the production AI profile is supportability rather than age. NVIDIA's current standalone GPU Operator matrix already validates newer Ubuntu 26.04 combinations for RKE2 and K3s, but the broader NVIDIA AI Enterprise 8.2 **bare-metal** matrix currently lists RKE2 on Ubuntu 20.04, 22.04 and 24.04 LTS. The same page lists RKE2 with Ubuntu 26.04 LTS guests in its virtualized table, and SUSE's own RKE2 v1.36 support matrix validates Ubuntu 26.04, so 26.04 is supportable; 24.04 is simply the combination that appears in the bare-metal enterprise matrix today. For production AI infrastructure, choose the combination that is validated together.

> **Latest is not automatically better than validated.**

## What NVIDIA uses

NVIDIA Enterprise Reference Architectures commonly use a stack based on:

```text
Ubuntu
  |
Upstream Kubernetes
  |
containerd
  |
GPU Operator
Network Operator
AI workload services
observability
```

That makes upstream Kubernetes the clearest neutral/reference implementation, but it does not mean it is the only supported production choice.

NVIDIA AI Enterprise 8.2 also lists **RKE2, OpenShift, Charmed Kubernetes, upstream Kubernetes, and managed services such as EKS/GKE/AKS** in supported combinations.

Official references:

- NVIDIA AI Enterprise 8.2 support matrix: <https://docs.nvidia.com/ai-enterprise/release-8/latest/support/support-matrix-8/8.2.html>
- NVIDIA Enterprise Reference Architecture: <https://docs.nvidia.com/enterprise-reference-architectures/enterprise-rag-deployment-guide/latest/enterprise-ra-overview.html>
- NVIDIA upstream Kubernetes deployment guide: <https://docs.nvidia.com/enterprise-reference-architectures/upstream-kubernetes-deployment-guide.pdf>

## Why RKE2 is the best fit here

### 1. NVIDIA AI Enterprise support

The current AI Enterprise 8.2 bare-metal matrix lists **SUSE Rancher RKE2** with Kubernetes versions `1.32-1.36`, `containerd`, and support for:

- NVIDIA GPU Operator;
- NVIDIA Network Operator;
- Run:ai;
- supported Ubuntu and RHEL combinations.

That gives RKE2 a stronger enterprise-AI support position than K3s today.

### 2. Straightforward HA

RKE2's HA design is simple and familiar:

```text
                     API / VIP / load balancer
                              |
          +-------------------+-------------------+
          |                   |                   |
     RKE2 server 1       RKE2 server 2       RKE2 server 3
     control plane       control plane       control plane
     embedded etcd       embedded etcd       embedded etcd
          |                   |                   |
          +-------------- quorum ----------------+
                              |
                  +-----------+-----------+
                  |                       |
             CPU workers             GPU workers
                                          |
                                 NVIDIA GPU Operator
                                          |
                                AI training / serving
```

RKE2 recommends an odd number of server nodes, with three recommended for HA.

Official references:

- RKE2 HA: <https://docs.rke2.io/install/ha>
- RKE2 embedded datastore: <https://docs.rke2.io/datastore/embedded>

### 3. Security and compliance orientation

RKE2 is positioned as an enterprise-ready Kubernetes distribution focused on security and compliance. Its documentation includes CIS hardening guidance, FIPS support, and Kubernetes secrets-encryption support.

Official references:

- RKE2 overview: <https://docs.rke2.io/>
- CIS hardening: <https://docs.rke2.io/security/hardening_guide>
- FIPS support: <https://docs.rke2.io/security/fips_support>
- Secrets encryption: <https://docs.rke2.io/security/secrets_encryption>

### 4. Dedicated NVIDIA GPU guidance

RKE2 has explicit documentation for deploying NVIDIA GPU Operator with its `containerd` layout.

- RKE2 GPU Operator guide: <https://docs.rke2.io/add-ons/gpu_operators>

## Why Kubernetes 1.36 is the current AI Factory baseline

For this project, **Kubernetes 1.36.x is sufficient for production AI inference and is the preferred conservative baseline today**.

The main reason is that it sits inside the current support overlap we care about:

| Capability / platform | Kubernetes 1.36 | Kubernetes 1.37 |
|---|---:|---:|
| NVIDIA GPU Operator on current RKE2 matrix | Yes | Yes |
| NVIDIA AI Enterprise 8.2 RKE2 matrix | **Yes** | Not currently listed |
| KServe 0.20 `LLMInferenceService` minimum | Yes (`1.32+`) | Yes |
| vLLM Kubernetes deployment model | Yes | Yes |
| Standard `nvidia.com/gpu` scheduling | Yes | Yes |
| Dynamic Resource Allocation foundation | **Stable** | Stable + newer enhancements |
| Production inference prerequisite | **Yes** | No additional requirement |

Kubernetes 1.36 already provides everything needed to run the inference layer of the AI Factory:

- Deployments and Services for long-running inference APIs;
- readiness, liveness and startup probes;
- rolling updates and self-healing;
- standard GPU scheduling through `nvidia.com/gpu`;
- NVIDIA GPU Operator compatibility;
- stable Dynamic Resource Allocation foundation;
- enough Kubernetes API level for KServe generative-AI serving;
- support for vLLM, KServe, KubeRay/Ray Serve and similar runtimes;
- storage, networking, RBAC, quotas and observability integration.

A basic GPU-backed inference request remains straightforward:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

Kubernetes schedules the Pod on a GPU-capable worker. The inference runtime — for example vLLM, KServe, Ray Serve, Triton or NIM — loads the model into RAM/VRAM and performs the actual model inference.

### What Kubernetes 1.37 adds

Kubernetes 1.37 contains useful accelerator-management and DRA improvements. Those are valuable for future sophisticated device allocation, but they do **not** make 1.36 incapable of AI inference.

Therefore:

```text
Need: production AI / LLM inference
               |
               v
      Kubernetes 1.36.x
               |
          sufficient today
               |
   +-----------+-----------+
   |                       |
GPU Operator              DRA
nvidia.com/gpu        stable foundation
   |                       |
   +-----------+-----------+
               |
       inference runtime
   vLLM / KServe / KubeRay
```

Do not upgrade to Kubernetes 1.37 only because the workload is called "AI." Move to 1.37 when the chosen RKE2 release and the complete driver, GPU Operator, serving, networking and observability stack are validated together, or when a specific 1.37 feature solves a real requirement.

Detailed inference guidance is documented in [`inference-workloads.md`](inference-workloads.md).

## Using a physical host GPU with Kubernetes

Kubernetes is still required in this project, but **NVIDIA AI Enterprise is not required just because the cluster uses a GPU that is physically installed in a host**.

If the hardware is an NVIDIA GPU, Kubernetes still needs a software path that exposes that GPU to pods:

```text
Physical NVIDIA GPU
        |
Ubuntu host
        |
NVIDIA Linux driver
        |
RKE2 / K3s
        |
containerd
        |
NVIDIA Container Toolkit
        |
NVIDIA Kubernetes device plugin
        |
Pod requests nvidia.com/gpu: 1
```

The key distinction is:

| Component | Required? | Why |
|---|---|---|
| Physical NVIDIA GPU | Yes, for NVIDIA acceleration | Provides the accelerator hardware |
| NVIDIA Linux driver | Yes | Lets the Linux host communicate with the GPU |
| Kubernetes | Yes for this project | Schedules and manages GPU workloads |
| NVIDIA Container Toolkit | Normally yes for NVIDIA GPU containers | Lets containerd launch GPU-enabled containers |
| NVIDIA Kubernetes device plugin | Yes for standard `nvidia.com/gpu` scheduling | Advertises GPU resources to Kubernetes |
| NVIDIA GPU Operator | **Optional but recommended** | Automates and manages the GPU software stack across nodes |
| NVIDIA AI Enterprise | **No** | Commercial enterprise software/support is not required for basic Kubernetes GPU use |

### Manual GPU integration

For a small lab or a single GPU worker, the GPU stack can be installed manually:

```text
Ubuntu
  |
NVIDIA driver
  |
NVIDIA Container Toolkit
  |
RKE2 / K3s + containerd
  |
NVIDIA device plugin
  |
GPU-enabled pod
```

This is a valid Kubernetes design and avoids requiring NVIDIA AI Enterprise.

The trade-off is that the platform team owns driver installation, toolkit configuration, device-plugin upgrades, compatibility validation and troubleshooting on every GPU node.

### Recommended AI Factory integration: GPU Operator

For a production AI Factory or multiple GPU workers, use the **NVIDIA GPU Operator** instead of manually maintaining every GPU integration component.

Conceptually:

```text
Ubuntu GPU worker
        |
RKE2 / K3s
        |
NVIDIA GPU Operator
        |
        +-- GPU driver lifecycle where configured
        +-- NVIDIA Container Toolkit integration
        +-- Kubernetes device plugin
        +-- GPU feature discovery
        +-- DCGM / GPU telemetry components
        |
GPU-enabled Kubernetes workloads
```

GPU Operator is separate from NVIDIA AI Enterprise. The operator itself can be used to integrate supported NVIDIA GPUs with Kubernetes without buying NVIDIA AI Enterprise.

For this repository, the preferred production pattern is therefore:

```text
3 x CPU RKE2 servers
        |
        +-- Kubernetes control plane / etcd
        |
N x GPU RKE2 agents
        |
        +-- physical NVIDIA GPUs
        +-- NVIDIA GPU Operator
        |
        +-- training
        +-- inference
        +-- RAG
        +-- agents
```

Keep expensive GPUs on worker/agent nodes. Do not place GPUs on control-plane nodes unless there is a specific reason to do so.

### What if the GPU is not NVIDIA?

The same Kubernetes principle applies, but the NVIDIA stack is replaced by the appropriate vendor integration.

```text
Physical GPU
   |
Linux driver
   |
container runtime integration
   |
Kubernetes vendor device plugin / operator
   |
GPU-enabled pod
```

For AMD or Intel accelerators, use the supported AMD/Intel Kubernetes device-management stack rather than NVIDIA GPU Operator. The exact driver, runtime and operator combination must be validated against the GPU model, OS and Kubernetes version.

## What about K3s?

K3s is still a valid AI platform.

The current NVIDIA GPU Operator support matrix validates K3s on recent Ubuntu/Kubernetes combinations, including Ubuntu 24.04 and Ubuntu 26.04.

So this is technically valid:

```text
Ubuntu
  |
K3s
  |
containerd
  |
NVIDIA GPU Operator
  |
GPU workloads
```

Official reference:

- NVIDIA GPU Operator platform support: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html>

The difference is support positioning:

| Area | K3s | RKE2 |
|---|---|---|
| Lightweight/simple operations | Excellent | Very good |
| GPU Operator validation | Yes | Yes |
| NVIDIA AI Enterprise bare-metal platform listing | Not currently listed as an orchestration platform | Yes |
| Network Operator in AI Enterprise matrix | Not as a K3s platform entry | Yes |
| Run:ai in AI Enterprise matrix | Not as a K3s platform entry | Yes |
| Security/compliance focus | Good | Stronger |
| Edge/small footprint | Excellent | Good |
| Production AI Factory default | Good for small/medium | **Recommended** |

Therefore the recommendation is not "K3s cannot do AI." It can. The recommendation is that **RKE2 has the stronger current enterprise support path for a serious self-hosted NVIDIA-oriented AI Factory**.

## What about upstream Kubernetes?

Choose upstream Kubernetes when direct alignment with NVIDIA reference architectures and maximum component control matter more than operational simplicity.

It is a strong option for organizations with a mature Kubernetes platform team that wants explicit ownership of:

- CNI;
- PKI;
- control-plane configuration;
- etcd lifecycle;
- upgrades;
- cluster bootstrap automation.

For a smaller team, RKE2 usually offers a better balance between control and operational overhead.

## What about OpenShift?

OpenShift is a strong option for a large enterprise that already standardizes on Red Hat and wants an integrated platform, strong governance, and vendor-backed lifecycle management.

It is also directly represented in NVIDIA AI Enterprise support matrices.

The trade-off is significantly more platform complexity and resource overhead than RKE2 or K3s.

## Managed AWS alternative

If self-hosting the Kubernetes control plane is no longer a requirement, **Amazon EKS** becomes a strong alternative. NVIDIA AI Enterprise 8.2 includes EKS in its managed-Kubernetes support matrix.

```text
AWS EKS
  |
  +-- CPU node groups
  +-- GPU EC2 node groups
          |
          +-- GPU Operator
          +-- Kueue / Run:ai
          +-- KServe / KubeRay / NIM
```

For this repository, however, the goal remains self-managed Kubernetes, so RKE2 is the better architectural comparison.

## Recommended ranking for this project

| Rank | Platform | Best fit |
|---:|---|---|
| **1** | **RKE2** | Self-hosted production AI Factory |
| **2** | **Upstream Kubernetes** | Maximum control and closest NVIDIA reference alignment |
| **3** | **OpenShift** | Large/compliance-heavy enterprise |
| **4** | **K3s** | Lightweight, edge, small/medium AI, labs and inference |
| **5** | **Charmed Kubernetes** | Canonical/Ubuntu-focused organizations |
| Managed | **Amazon EKS** | AWS-managed control plane |

## Recommended production topology

```text
                       stable Kubernetes API endpoint
                                  |
                 +----------------+----------------+
                 |                |                |
           RKE2 server 1    RKE2 server 2    RKE2 server 3
           Ubuntu 24.04     Ubuntu 24.04     Ubuntu 24.04
           CPU / etcd       CPU / etcd       CPU / etcd
                 |                |                |
                 +---------- HA quorum ------------+
                                  |
              +-------------------+-------------------+
              |                                       |
        CPU worker pool                         GPU worker pool
        platform services                       AI workloads
                                                      |
                                           NVIDIA GPU Operator
                                           DCGM / observability
                                                      |
                               training / inference / RAG / agents
```

Keep the control plane on CPU nodes. etcd, kube-apiserver, controllers, Argo CD and cert-manager do not need expensive GPUs. GPU capacity should scale independently and be reserved for AI workloads.

## Repository evolution

Do not remove the current K3s profile. Treat the two distributions as profiles for different goals:

```text
K3s profile
  -> lightweight/general Kubernetes
  -> development, learning, smaller production
  -> current repository path

RKE2 AI Factory profile
  -> production GPU platform
  -> Kubernetes 1.36.x baseline
  -> HA control plane
  -> dedicated GPU workers
  -> NVIDIA enterprise-oriented stack
```

Suggested evolution:

1. Keep the current Ubuntu + K3s platform for general Kubernetes development.
2. Build and validate a three-server HA topology.
3. Add an RKE2 AI Factory profile based on Ubuntu 24.04 LTS and Kubernetes 1.36.x.
4. Add dedicated GPU agents and GPU Operator.
5. Start inference simply with vLLM behind a Kubernetes Service.
6. Add KServe or KubeRay when model lifecycle, autoscaling or distributed serving requirements justify them.
7. Add Kueue or Run:ai, DCGM/Prometheus, and model-serving components only when needed.
8. Add Network Operator, RDMA, GPUDirect RDMA and high-throughput shared storage only when distributed workloads require them.
9. Move to Kubernetes 1.37 after the complete selected stack is validated together and a 1.37 capability provides a real operational benefit.

## Final decision

For this repository, the recommended direction is:

> **Keep K3s as the lightweight/default Kubernetes profile, and use RKE2 with Kubernetes 1.36.x as the current production AI Factory baseline.**

Recommended production AI Factory baseline:

```text
Ubuntu Server 24.04 LTS
+
RKE2 / Kubernetes 1.36.x
+
3 CPU control-plane/etcd servers
+
dedicated GPU agents
+
NVIDIA GPU Operator
+
Network Operator only where required
+
vLLM for the first inference service
+
Kueue or Run:ai when scheduling/quotas require it
+
KServe / KubeRay / NIM according to workload
+
Prometheus / Grafana / DCGM
+
Argo CD
```

For GPU access, remember the licensing boundary:

> **Owning and using a physical NVIDIA GPU with Kubernetes does not require NVIDIA AI Enterprise.** Kubernetes still needs the NVIDIA driver/runtime/device integration, and GPU Operator is the recommended automation layer for production clusters.

For inference, remember the version boundary:

> **Kubernetes 1.36 already supports the production inference architecture we need. Kubernetes 1.37 is an upgrade target, not a prerequisite.**

## Official sources

- NVIDIA AI Enterprise 8.2 support matrix: <https://docs.nvidia.com/ai-enterprise/release-8/latest/support/support-matrix-8/8.2.html>
- NVIDIA GPU Operator platform support: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html>
- NVIDIA GPU Operator documentation: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/>
- NVIDIA Network Operator platform support: <https://docs.nvidia.com/networking/display/kubernetes2670/platform-support.html>
- NVIDIA Enterprise Reference Architecture: <https://docs.nvidia.com/enterprise-reference-architectures/enterprise-rag-deployment-guide/latest/enterprise-ra-overview.html>
- Kubernetes Dynamic Resource Allocation: <https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/>
- Kubernetes 1.36 DRA updates: <https://kubernetes.io/blog/2026/05/07/kubernetes-v1-36-dra-136-updates/>
- Kubernetes 1.36 release: <https://kubernetes.io/blog/2026/04/22/kubernetes-v1-36-release/>
- KServe LLMInferenceService requirements: <https://kserve.github.io/website/docs/admin-guide/kubernetes-deployment-llmisvc>
- vLLM on Kubernetes: <https://docs.vllm.ai/en/latest/deployment/k8s/>
- RKE2: <https://docs.rke2.io/>
- RKE2 HA: <https://docs.rke2.io/install/ha>
- RKE2 embedded datastore: <https://docs.rke2.io/datastore/embedded>
- RKE2 GPU Operator: <https://docs.rke2.io/add-ons/gpu_operators>
- RKE2 CIS hardening: <https://docs.rke2.io/security/hardening_guide>
- RKE2 FIPS support: <https://docs.rke2.io/security/fips_support>
