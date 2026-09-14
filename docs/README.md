# Repository architecture

The repository separates AWS networking, EC2 compute, K3s configuration and Kubernetes add-ons into independent **Terragrunt units**. Terragrunt is the single operator interface for plan/apply/destroy.

## Architecture and research guides

- [`../README.md`](../README.md) - the main AI Factory guide (repository README): what an AI factory is, where Kubernetes/K3s fits, GPU/platform architecture, pros/cons, distribution choices, repository evolution path, and current official source links.
- [`ai-factory/kubernetes-distribution-recommendation.md`](ai-factory/kubernetes-distribution-recommendation.md) - focused research on the recommended Kubernetes distribution for a self-hosted production AI Factory, including RKE2 vs upstream Kubernetes vs OpenShift vs K3s, NVIDIA support matrices, HA design, and the Ubuntu 24.04 validation rationale.
- [`ai-factory/inference-workloads.md`](ai-factory/inference-workloads.md) - explains AI inference, how Kubernetes serves trained models, host-GPU integration, vLLM/KServe/KubeRay patterns, and why Kubernetes 1.36 is sufficient for the current production AI Factory baseline.
- [`ai-factory/llm-gateway/README.md`](ai-factory/llm-gateway/README.md) - LiteLLM-focused production LLM Gateway design and Helm installation guide, including requirements, secrets, PostgreSQL/Redis, Traefik/TLS, vLLM integration, HA, scaling, observability, upgrades, rollback, and the future Gateway API Inference Extension path.
- [`ai-factory/llm-gateway/gateway-api.md`](ai-factory/llm-gateway/gateway-api.md) - **Traefik + LiteLLM-specific** Gateway API setup: Gateway API CRDs, Traefik Gateway API provider, cert-manager integration, TLS and HTTPRoute to LiteLLM. This is not the AgentGateway installation path.
- [`ai-factory/agent-gateway/README.md`](ai-factory/agent-gateway/README.md) - Kubernetes-native **AgentGateway** path: Gateway API prerequisite, current `v1.5.0` pin, separate CRD/control-plane OCI Helm charts, `GatewayClass: agentgateway`, Gateway and HTTPRoute setup, direct vLLM and MCP backends, coexistence with Traefik, and optional Gateway API Inference Extension.
- [`ai-factory/llm-kube/README.md`](ai-factory/llm-kube/README.md) - LLMKube evaluation for the AI Factory: what the operator does, whether it is actually needed, current Helm installation, Kubernetes/GPU/storage requirements, vLLM and LiteLLM integration, GitOps, observability, scaling, upgrade/rollback, and a staged adoption recommendation.
- [`ai-factory/mcp-gateway/README.md`](ai-factory/mcp-gateway/README.md) - MCP Gateway evaluation and production Helm guide using IBM ContextForge, including MCP concepts, MCP Gateway vs LiteLLM/LLMKube, the current `v1.0.10` pin, Kubernetes 1.36 requirements, Traefik/TLS, secrets, strict SSRF policy, PostgreSQL/Redis, HA/HPA, observability, GitOps, security, upgrade/rollback, and when the AI Factory actually needs an MCP gateway.
- [`ai-factory/ai-playground/README.md`](ai-factory/ai-playground/README.md) - local AI playground on an Apple Silicon Mac: why Rancher Desktop cannot pass the GPU to pods, the Vulkan/krunkit bridge, minikube + krunkit + generic-device-plugin setup, and a GPU-scheduled Gemma pod.
- [`platform/README.md`](platform/README.md) - K3s platform deployment guide: prerequisites, Terragrunt-only deploy, EC2 `for_each`, deletion protection, kubeconfig, destroy and migration.
- [`terragrunt-workflow/README.md`](terragrunt-workflow/README.md) - canonical deployment workflow: backend bootstrap, run-all DAG, component operations, kubeconfig output, state/security and migration.
- [`kubernetes-platform-comparison/README.md`](kubernetes-platform-comparison/README.md) - central comparison of K3s, RKE2, Talos Linux, k0s, MicroK8s, kubeadm, k3d and Compose.
- [`k3s-vs-kubeadm/README.md`](k3s-vs-kubeadm/README.md) - K3s vs kubeadm research, HA/non-HA, K3s-in-Docker and distribution choices.
- [`k3s-vs-kubeadm/open-source-kubernetes-landscape.md`](k3s-vs-kubeadm/open-source-kubernetes-landscape.md) - open-source project roles and licensing.
- [`k3s-vs-kubeadm/architecture.svg`](k3s-vs-kubeadm/architecture.svg) - visual K3s/kubeadm comparison.
- [`k3s/README.md`](k3s/README.md) and [`k3s/architecture.md`](k3s/architecture.md) - K3s topology guidance.
- [`diagrams/k3s-platform-overview.svg`](diagrams/k3s-platform-overview.svg) - AWS/K3s platform architecture.

## Terragrunt dependency graph

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

Each component has its own state boundary:

```text
infrastructure/
├── modules/
│   ├── vpc/
│   ├── ec2/
│   ├── k3s/
│   └── helm-release/
└── live/
    ├── root.hcl
    ├── _common/
    │   ├── vpc.hcl
    │   ├── ec2.hcl
    │   ├── k3s.hcl
    │   ├── traefik.hcl
    │   ├── cert-manager.hcl
    │   └── argocd.hcl
    └── dev/
        ├── env.hcl
        └── us-east-1/
            ├── region.hcl
            ├── vpc/terragrunt.hcl
            ├── ec2/terragrunt.hcl
            ├── k3s/terragrunt.hcl
            ├── traefik/terragrunt.hcl
            ├── cert-manager/terragrunt.hcl
            └── argocd/terragrunt.hcl
```

## Lifecycle boundaries

- `vpc` owns networking.
- `ec2` owns EC2, EIP, IAM/SSM access, security groups, EBS and the node bootstrap delivered as user data.
- `k3s` owns kubeconfig retrieval and exposes the client material to the add-on units.
- `traefik`, `cert-manager` and `argocd` consume K3s outputs and manage official upstream charts through Terraform `helm_release` resources.

The K3s version is rendered into the node bootstrap, so changing it replaces the EC2 instance. Updating a chart version only changes the corresponding Helm unit.

## Design rules

1. **Terragrunt is the operator interface.** No Makefile or deployment shell wrapper is required.
2. **One concern per module/state.** EC2, K3s and each platform add-on have independent lifecycle/state boundaries.
3. **Reusable modules contain no environment values.** Environment-specific values stay under `infrastructure/live`.
4. **Shared component defaults live once.** Baseline sizing, K3s version and Helm chart pins live under `infrastructure/live/_common`.
5. **Leaf units only wire dependencies and overrides.** A new region does not copy Terraform module logic.
6. **Dependencies are explicit.** K3s consumes EC2 outputs; platform add-ons consume K3s connection outputs.
7. **Version upgrades are explicit.** Runtime/provider/chart versions are pinned and auditable in Git.
8. **Secrets stay out of Git.** K3s client material is sensitive, held in protected remote state and in a local kubeconfig written outside the repository.

## Add another region

Create thin units:

```text
infrastructure/live/dev/eu-west-1/
├── region.hcl
├── vpc/terragrunt.hcl
├── ec2/terragrunt.hcl
├── k3s/terragrunt.hcl
├── traefik/terragrunt.hcl
├── cert-manager/terragrunt.hcl
└── argocd/terragrunt.hcl
```

Then operate from that region directory:

```bash
terragrunt run --all plan
terragrunt run --all apply
```

## State migration note

An older repository revision used a combined `k3s-ec2` state, and an intermediate revision installed platform Helm releases outside Terraform state. Existing environments must migrate/import those resources before applying this layout. New deployments require no migration.
