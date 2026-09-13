# AI inference workloads on Kubernetes

> **Research review:** 2026-09-13. Checked against current Kubernetes 1.36 documentation, NVIDIA GPU Operator platform support, KServe 0.20 LLMInferenceService requirements, and current vLLM Kubernetes deployment guidance.

## What inference means

**Inference** is the production phase where an already-trained AI model receives an input and returns an output.

Training teaches the model:

```text
training data
     |
     v
model learns
     |
     v
trained model / model weights
```

Inference uses that trained model:

```text
user / application request
          |
          v
     trained model
          |
          v
answer / prediction / generated output
```

Examples:

| Workload | Input | Inference output |
|---|---|---|
| LLM | prompt | generated text / tool call |
| RAG | question + retrieved context | grounded answer |
| Vision | image | classification / detection |
| Speech | audio | transcription |
| Recommendation | user/context | ranked recommendations |
| Fraud model | transaction | risk score |

Inference is different from training. Training is normally a long-running compute job that produces or changes model weights. Inference normally exposes a trained model as an online or batch service that applications call repeatedly.

## Where Kubernetes fits

For an AI Factory, Kubernetes is the control plane around the inference service. Kubernetes does not perform the model calculation itself; it schedules and operates the software that does.

A typical request path is:

```text
user / application
       |
       v
Ingress / Gateway
       |
       v
Kubernetes Service
       |
       v
Inference Pod
vLLM / KServe / Ray Serve / Triton / NIM
       |
       v
model loaded into RAM / GPU VRAM
       |
       v
CPU / GPU
       |
       v
response
```

Kubernetes provides the surrounding production capabilities:

- placement of inference Pods on GPU-capable nodes;
- restarts and self-healing;
- rolling upgrades;
- Services and networking;
- readiness/liveness/startup probes;
- secrets and configuration;
- CPU, memory and GPU resource requests;
- autoscaling and replica management;
- multi-tenancy and RBAC;
- storage for model caches and artifacts;
- observability integration;
- scheduling across heterogeneous accelerator nodes.

## Can Kubernetes 1.36 run production AI inference?

**Yes. Kubernetes 1.36 is fully capable of running the inference layer we want for this AI Factory. Kubernetes 1.37 is not required for this goal.**

For this project, Kubernetes 1.36 provides the important building blocks already:

1. mature Deployments, Services, probes, scheduling and autoscaling for long-running inference APIs;
2. standard extended resources such as `nvidia.com/gpu` through the NVIDIA device-plugin / GPU Operator path;
3. Dynamic Resource Allocation (DRA), which has been stable since Kubernetes 1.35;
4. further DRA improvements in Kubernetes 1.36, including stable prioritized device requests and stable admin access;
5. support from the current NVIDIA GPU Operator matrix;
6. enough Kubernetes API level for current KServe generative-AI serving components.

The current NVIDIA GPU Operator platform matrix validates Ubuntu 24.04 and Ubuntu 26.04 with RKE2 across Kubernetes `1.33-1.37`, so **1.36 is inside the validated range**.

KServe 0.20 documents Kubernetes `1.32+` as the minimum for its `LLMInferenceService` (alongside Gateway API Inference Extension 1.2.0), which means Kubernetes 1.36 is comfortably above that requirement. KServe 0.16, cited in an earlier revision of this guide, is no longer maintained.

vLLM's current documentation provides native Kubernetes GPU deployment examples using ordinary Deployments, Services, persistent volumes and accelerator resource requests. These do not depend on Kubernetes 1.37.

## What Kubernetes 1.37 adds

Kubernetes 1.37 contains useful accelerator-management improvements, but they are **enhancements rather than a prerequisite for inference**.

For example, extended-resource allocation backed by DRA becomes stable in Kubernetes 1.37. This improves the migration path between the traditional extended-resource model and DRA-managed devices.

That is valuable for future sophisticated GPU scheduling, but a production inference Pod can already request a GPU on 1.36 using the established model:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

Therefore the decision is:

```text
Need: serve AI/LLM inference on Kubernetes
                 |
                 v
        Kubernetes 1.36
                 |
              enough
                 |
       +---------+---------+
       |                   |
standard GPU path       DRA available
nvidia.com/gpu          stable foundation
       |                   |
       +---------+---------+
                 |
         inference runtime
       vLLM / KServe / Ray
```

Do not upgrade to 1.37 only because the workload is called "AI". Upgrade when the full platform stack has been validated and a 1.37 feature provides a concrete operational benefit.

## Recommended inference architecture for this project

For the future production AI Factory profile:

```text
                       stable Kubernetes API endpoint
                                  |
                 +----------------+----------------+
                 |                |                |
           RKE2 server 1    RKE2 server 2    RKE2 server 3
           CPU / etcd       CPU / etcd       CPU / etcd
           Ubuntu 24.04     Ubuntu 24.04     Ubuntu 24.04
                 |                |                |
                 +---------- HA quorum ------------+
                                  |
                                  v
                         Kubernetes 1.36
                                  |
                 +----------------+----------------+
                 |                                 |
          CPU worker pool                   GPU worker pool
      platform / normal apps                 host NVIDIA GPU
                                                   |
                                          NVIDIA GPU Operator
                                                   |
                                   +---------------+---------------+
                                   |               |               |
                                 vLLM            KServe          KubeRay
                                   |               |               |
                                   +---------------+---------------+
                                                   |
                                            model inference
                                                   |
                                            API / applications
```

The expensive GPU nodes should be dedicated to workloads that benefit from accelerators. The control plane, etcd, Argo CD, cert-manager, DNS and other platform services should remain on CPU nodes.

## Host GPU and Kubernetes

If the GPU is physically installed in the host, Kubernetes can use it. NVIDIA AI Enterprise licensing is not required merely to expose a local NVIDIA GPU to a Kubernetes Pod.

The open-source integration path is:

```text
physical NVIDIA GPU
        |
Ubuntu host
        |
NVIDIA driver
        |
RKE2 / containerd
        |
NVIDIA Container Toolkit
        |
NVIDIA device plugin / GPU Operator
        |
Kubernetes sees nvidia.com/gpu
        |
inference Pod
```

For one lab GPU node, the driver, Container Toolkit and device plugin can be managed manually. For a production AI Factory or several GPU workers, **NVIDIA GPU Operator is preferred** because it manages more of the GPU software lifecycle consistently across the cluster.

## Example: simple vLLM inference Pod

Conceptually, an inference workload can request a GPU like this:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vllm
  template:
    metadata:
      labels:
        app: vllm
    spec:
      containers:
        - name: vllm
          image: vllm/vllm-openai:latest
          args:
            - --model
            - <model-name>
          ports:
            - containerPort: 8000
          resources:
            limits:
              nvidia.com/gpu: 1
---
apiVersion: v1
kind: Service
metadata:
  name: vllm
spec:
  selector:
    app: vllm
  ports:
    - port: 80
      targetPort: 8000
```

The exact production manifest should pin the image and model versions, define CPU/memory requests, configure model storage, secrets, probes, security context, topology/scheduling rules and observability. The example above only shows the relationship between Kubernetes and the GPU-backed inference runtime.

## Inference platform maturity path

Start simple and add components only when the workload requires them:

```text
Stage 1
Kubernetes Deployment + Service + vLLM
        |
Stage 2
GPU Operator + model storage + monitoring
        |
Stage 3
KServe / KubeRay / production vLLM stack
        |
Stage 4
Kueue / advanced scheduling / multi-team quotas
        |
Stage 5
multi-node inference / LeaderWorkerSet / advanced DRA
```

This avoids making the initial inference platform more complicated than the workload requires.

## Decision for this repository

For the production AI Factory profile, **Kubernetes 1.36 is sufficient for GPU-backed inference and is currently the preferred conservative baseline**.

```text
Ubuntu Server 24.04 LTS
+
RKE2 / Kubernetes 1.36.x
+
containerd
+
physical NVIDIA GPU workers
+
NVIDIA GPU Operator
+
vLLM initially
+
KServe / KubeRay when required
+
Prometheus / Grafana / DCGM
+
Argo CD
```

Use Kubernetes 1.37 later when the selected RKE2 release and the complete GPU/serving stack have been validated together and when its newer DRA capabilities solve a real requirement.

## Official references

- Kubernetes Dynamic Resource Allocation: <https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/>
- Kubernetes 1.36 DRA updates: <https://kubernetes.io/blog/2026/05/07/kubernetes-v1-36-dra-136-updates/>
- Kubernetes 1.36 release: <https://kubernetes.io/blog/2026/04/22/kubernetes-v1-36-release/>
- NVIDIA GPU Operator platform support: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html>
- KServe LLMInferenceService Kubernetes deployment requirements: <https://kserve.github.io/website/docs/admin-guide/kubernetes-deployment-llmisvc>
- vLLM on Kubernetes: <https://docs.vllm.ai/en/latest/deployment/k8s/>
- vLLM production stack: <https://docs.vllm.ai/en/stable/deployment/integrations/production-stack/>
