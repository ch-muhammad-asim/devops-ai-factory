# AI Factory guides

The main AI Factory guide is the repository [`README.md`](../../README.md). This directory holds the supporting research and Helm guides:

- [`kubernetes-distribution-recommendation.md`](kubernetes-distribution-recommendation.md) - RKE2 vs upstream Kubernetes vs OpenShift vs K3s for a production AI Factory.
- [`inference-workloads.md`](inference-workloads.md) - AI inference on Kubernetes, host GPU integration, vLLM/KServe/KubeRay.
- [`llm-gateway/README.md`](llm-gateway/README.md) - LiteLLM LLM gateway; [`llm-gateway/gateway-api.md`](llm-gateway/gateway-api.md) and [`llm-gateway/agentgateway.md`](llm-gateway/agentgateway.md) cover the Gateway API paths.
- [`llm-kube/README.md`](llm-kube/README.md) - LLMKube operator evaluation.
- [`mcp-gateway/README.md`](mcp-gateway/README.md) - IBM ContextForge MCP gateway.
- [`architecture.svg`](architecture.svg) / [`architecture.png`](architecture.png) - simple AI Factory architecture visual.

The Kubernetes substrate these guides run on is documented in [`../platform/README.md`](../platform/README.md).
