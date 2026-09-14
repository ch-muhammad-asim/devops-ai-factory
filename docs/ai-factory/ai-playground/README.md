# AI playground on an Apple Silicon Mac

> **Research review:** 2026-09-14. Checked against the minikube krunkit driver and AI playground tutorial, the Lima krunkit documentation, the Rancher Desktop GPU issue tracker, Red Hat's libkrun/Venus write-ups, llama.cpp container benchmarks, and the LLMKube Metal Agent documentation.

This guide answers one question: **how do I learn AI on Kubernetes locally on a Mac, with pods that get the GPU the way they do in a real cluster?** It complements the cloud path in the rest of `docs/ai-factory/`, where GPU nodes are NVIDIA machines on AWS.

## Decision

Use **minikube with the krunkit driver** plus the generic device plugin. It is the only local option today where a pod requests a GPU resource, the scheduler enforces it, and the inference server runs inside the pod with GPU acceleration.

**Rancher Desktop cannot do this.** It runs Kubernetes in a Lima virtual machine without GPU passthrough, and the feature request has been open since September 2023 with no shipped support. Keep it for ordinary container and Kubernetes work; it is not the tool for GPU pods.

## The hardware fact behind every option

Every Kubernetes distribution on a Mac runs inside a Linux virtual machine. Apple's GPU API, Metal, exists only in macOS, so a Linux pod can never call Metal directly.

The one bridge that exists is Vulkan:

```text
pod: llama.cpp built with the Vulkan backend
        |
Mesa Venus driver (Vulkan calls encoded as messages)
        |
virtio-gpu shared memory into the macOS host
        |
virglrenderer -> MoltenVK (Vulkan translated to Metal)
        |
Apple GPU cores
```

The hypervisor that implements this bridge is **krunkit**, built on libkrun. Whatever tool you choose, GPU-in-pod on a Mac means krunkit underneath. Measured token generation inside such a container is roughly 80% of native Metal.

## Options compared

| Option | GPU visible inside the pod | How it works | Status |
|---|---|---|---|
| Rancher Desktop | No | Lima VM (VZ or QEMU) without GPU passthrough | Stable, CPU only |
| Docker Desktop | No, for containers | Docker Model Runner runs llama.cpp natively on the host with Metal, outside any container | Stable, host side only |
| LLMKube Metal Agent | No pod at all | A `launchd` process on macOS runs `llama-server` with Metal and registers a Service into the cluster | Newer; fastest option |
| **minikube + krunkit** | **Yes** | krunkit exposes the GPU as `/dev/dri`; generic-device-plugin advertises `devic.es/dri`; pods request it; llama.cpp's Vulkan build uses it | Experimental; minikube 1.37+, macOS 14+ |

Lima 2.0 gained an experimental krunkit VM type, so Rancher Desktop could inherit this in the future because it is built on Lima. It does not expose it today.

## What "just like a real environment" you get, and what you do not

You get the Kubernetes semantics that matter for learning:

- a device plugin DaemonSet advertising a GPU resource on the node;
- pods that request the resource and stay `Pending` when none is free;
- the inference server running inside the pod, not on the host;
- normal Services, port-forwarding, Ingress, HPA, and GitOps on top.

Two things stay different from a production NVIDIA cluster, and no Mac option changes them:

- The resource is `devic.es/dri`, not `nvidia.com/gpu`. There is no GPU Operator, driver container, MIG, or DCGM.
- There is **no CUDA**. vLLM, TGI, KServe GPU runtimes, and PyTorch CUDA images will not use the Mac GPU. Only Vulkan-capable runtimes work, and llama.cpp is the practical one.

For CUDA, GPU Operator, vLLM, and KServe, rent a cloud GPU node for a few hours. That is what the AI Factory roadmap already plans.

## Reference machine

The setup below was sized for this machine. Adjust the memory numbers for yours.

| Item | Value |
|---|---|
| Machine | MacBook Pro, Apple M2 Pro |
| CPU | 10 cores (6 performance, 4 efficiency) |
| GPU | 16 cores, Metal 4 |
| Unified memory | 16 GB, shared between CPU and GPU |
| macOS | 26.6 |
| Disk free | about 150 GB |

**Memory is the ceiling.** The VM, the Kubernetes components, and the model share the 16 GB with macOS. Budget about 8 GB for the minikube VM. Inside it, Gemma 3 1B and 4B in Q4 are comfortable, an 8B model in Q4 is the practical limit, and anything larger will swap or fail. Keep the context size modest for the same reason.

Check your own values:

```bash
system_profiler SPHardwareDataType | grep -E 'Chip|Cores|Memory'
```

```bash
sw_vers
```

## Prerequisites

- Apple Silicon Mac on macOS 14 or later.
- Homebrew.
- `kubectl` (any recent version; minikube also bundles one).

## Step 1: install krunkit, vmnet-helper, and minikube

```bash
brew tap libkrun/krun && brew trust libkrun/krun && brew install krunkit
```

On macOS 26 or later:

```bash
brew tap nirs/vmnet-helper && brew trust nirs/vmnet-helper && brew install vmnet-helper
```

On macOS 15 or earlier, use the installer script instead:

```bash
curl -fsSL https://github.com/minikube-machine/vmnet-helper/releases/latest/download/install.sh | bash
```

```bash
brew install minikube
```

Verify:

```bash
krunkit --version
```

```bash
minikube version
```

## Step 2: download a model

llama.cpp needs GGUF files. Keep them on the host and mount the directory into the VM so pods read them without re-downloading. The same Gemma conversion used in the LLMKube guide is a good first model: it is not gated and is 806 MB in Q4_K_M.

```bash
mkdir -p ~/models && curl -L -o ~/models/gemma-3-1b-it-Q4_K_M.gguf https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf
```

For gated repositories, accept the terms on the model page while logged in and pass a Hugging Face read token as `-H "Authorization: Bearer $HF_TOKEN"`. The LLMKube guide explains Hugging Face accounts, gated models, and tokens in detail.

## Step 3: start the cluster with the GPU exposed

```bash
minikube start --driver krunkit --memory 8192 --cpus 4 --mount-string ~/models:/mnt/models
```

minikube prints that the krunkit driver is experimental. Confirm the GPU device exists inside the VM:

```bash
minikube ssh -- ls -l /dev/dri
```

You should see `card0` and `renderD128`.

## Step 4: advertise the GPU to the scheduler

Kubernetes does not know about `/dev/dri` until a device plugin advertises it. The generic device plugin publishes it as the resource `devic.es/dri`. Save as `device-plugin.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: generic-device-plugin
  namespace: kube-system
  labels:
    app.kubernetes.io/name: generic-device-plugin
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: generic-device-plugin
  template:
    metadata:
      labels:
        app.kubernetes.io/name: generic-device-plugin
    spec:
      priorityClassName: system-node-critical
      tolerations:
        - operator: "Exists"
          effect: "NoExecute"
        - operator: "Exists"
          effect: "NoSchedule"
      containers:
        - name: generic-device-plugin
          image: squat/generic-device-plugin
          args:
            - --device
            - |
              name: dri
              groups:
                - count: 4
                  paths:
                    - path: /dev/dri
          resources:
            requests:
              cpu: 50m
              memory: 10Mi
            limits:
              cpu: 50m
              memory: 20Mi
          ports:
            - containerPort: 8080
              name: http
          securityContext:
            privileged: true
          volumeMounts:
            - name: device-plugin
              mountPath: /var/lib/kubelet/device-plugins
            - name: dev
              mountPath: /dev
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
        - name: dev
          hostPath:
            path: /dev
  updateStrategy:
    type: RollingUpdate
```

`count: 4` lets up to four pods share the single GPU at once. Raise it for more.

```bash
kubectl apply -f device-plugin.yaml
```

```bash
kubectl get node minikube -o jsonpath='{.status.allocatable.devic\.es/dri}{"\n"}'
```

The output `4` means the node now advertises the GPU.

## Step 5: run Gemma in a GPU pod

Save as `gemma.yaml`. The image is RamaLama's llama.cpp build with the Vulkan backend, and `-ngl 999` offloads every layer to the GPU:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gemma
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gemma
  template:
    metadata:
      labels:
        app: gemma
    spec:
      containers:
        - name: llama-server
          image: quay.io/ramalama/ramalama:latest
          command:
            - llama-server
            - --host
            - "0.0.0.0"
            - --port
            - "8080"
            - --model
            - /mnt/models/gemma-3-1b-it-Q4_K_M.gguf
            - --alias
            - gemma-3-1b-it
            - --ctx-size
            - "2048"
            - -ngl
            - "999"
            - --threads
            - "4"
            - --no-warmup
          ports:
            - containerPort: 8080
          resources:
            limits:
              devic.es/dri: 1
              memory: 2Gi
          volumeMounts:
            - name: models
              mountPath: /mnt/models
      volumes:
        - name: models
          hostPath:
            path: /mnt/models
---
apiVersion: v1
kind: Service
metadata:
  name: gemma
spec:
  selector:
    app: gemma
  ports:
    - port: 8080
      targetPort: 8080
```

```bash
kubectl apply -f gemma.yaml
```

```bash
kubectl rollout status deploy/gemma
```

Confirm the GPU was actually used. The log should name a Vulkan device and show all layers offloaded:

```bash
kubectl logs deploy/gemma | grep -iE 'vulkan|offloaded'
```

## Step 6: talk to it

```bash
kubectl port-forward svc/gemma 8080:8080
```

```bash
curl -s http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"gemma-3-1b-it","messages":[{"role":"user","content":"In two sentences, what is Kubernetes?"}],"max_tokens":120}'
```

Expect tens of tokens per second on an M2 Pro. Compare with the CPU-only run from the LLMKube guide on the AWS node to feel the difference.

## Step 7: prove the scheduling works like production

Scale to more replicas than the device plugin allows and watch the extras stay `Pending` with an insufficient `devic.es/dri` event, exactly as `nvidia.com/gpu` behaves on a real cluster:

```bash
kubectl scale deploy/gemma --replicas=5
```

```bash
kubectl get pods -l app=gemma
```

```bash
kubectl describe pod -l app=gemma | grep -A3 Events | tail -5
```

Scale back:

```bash
kubectl scale deploy/gemma --replicas=1
```

## Going further

- **Open WebUI.** The minikube tutorial adds an Open WebUI Deployment pointed at the model Services through `OPENAI_API_BASE_URLS`. Use it for a chat interface.
- **Traefik, cert-manager, Argo CD.** Install the same charts pinned in this repository (`infrastructure/live/_common/*.hcl`) into minikube to rehearse the platform layer locally.
- **LiteLLM or AgentGateway.** Point either at `http://gemma.default.svc:8080/v1` to practise the gateway layer from `docs/ai-factory/llm-gateway/` and `docs/ai-factory/agent-gateway/`.
- **LLMKube Metal Agent.** For maximum speed on larger models, LLMKube can run `llama-server` natively on macOS with Metal and register it as a Service in this cluster. Nothing then runs in a pod, so use it for throughput, not for learning GPU scheduling.

## Cleanup

```bash
minikube stop
```

```bash
minikube delete
```

The models in `~/models` are untouched.

## Troubleshooting

- **`minikube start` fails on networking.** vmnet-helper is missing or not trusted. Re-run the vmnet-helper install for your macOS version.
- **Node shows no `devic.es/dri`.** The device plugin pod is not running; check `kubectl -n kube-system get pods -l app.kubernetes.io/name=generic-device-plugin`.
- **Pod runs but the log shows no Vulkan device.** The image lacks the Vulkan backend or `/dev/dri` was not mounted; confirm the `devic.es/dri` limit is set, since the device plugin injects the device only for pods that request it.
- **Pod is OOM-killed.** Lower `--ctx-size`, pick a smaller quantization, or give the VM more memory at `minikube start`.

## Official references

- minikube krunkit driver: <https://minikube.sigs.k8s.io/docs/drivers/krunkit/>
- minikube AI playground on Apple silicon: <https://minikube.sigs.k8s.io/docs/tutorials/ai-playground/>
- Lima krunkit VM type: <https://lima-vm.io/docs/config/vmtype/krunkit/>
- Rancher Desktop GPU support issue: <https://github.com/rancher-sandbox/rancher-desktop/issues/5561>
- Enabling containers to access the GPU on macOS (libkrun author): <https://sinrega.org/2024-03-06-enabling-containers-gpu-macos/>
- Red Hat, AI inference in macOS Podman containers: <https://developers.redhat.com/articles/2025/06/05/how-we-improved-ai-inference-macos-podman-containers>
- llama.cpp GPU-accelerated container benchmarks: <https://github.com/ggml-org/llama.cpp/discussions/12985>
- Docker Model Runner Vulkan support: <https://www.docker.com/blog/docker-model-runner-vulkan-gpu-support/>
- LLMKube Metal Agent: <https://llmkube.com/blog/kubernetes-metal-gpu-without-containers>
- generic-device-plugin: <https://github.com/squat/generic-device-plugin>
