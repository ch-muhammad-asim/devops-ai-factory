# AI Factory guides

The main AI Factory guide is the repository [`README.md`](../../README.md). This directory holds the supporting research and Helm guides:

- [`ai-llm-concepts-for-everyone.md`](ai-llm-concepts-for-everyone.md) - beginner-friendly AI/LLM vocabulary and mental models: tokens, prompts, temperature, context, RAG, embeddings, agents, tools, MCP, gateways, inference runtimes, quantization, GPUs, Kubernetes and the AI Factory.
- [`kubernetes-distribution-recommendation.md`](kubernetes-distribution-recommendation.md) - RKE2 vs upstream Kubernetes vs OpenShift vs K3s for a production AI Factory.
- [`inference-workloads.md`](inference-workloads.md) - AI inference on Kubernetes, host GPU integration, vLLM/KServe/KubeRay.
- [`llm-gateway/README.md`](llm-gateway/README.md) - LiteLLM LLM gateway; [`llm-gateway/gateway-api.md`](llm-gateway/gateway-api.md) covers the Traefik Gateway API path in front of it.
- [`agent-gateway/README.md`](agent-gateway/README.md) - AgentGateway, a Gateway API-native gateway for LLM, MCP and A2A traffic, and when to prefer it over LiteLLM.
- [`llm-kube/README.md`](llm-kube/README.md) - LLMKube operator evaluation.
- [`mcp-gateway/README.md`](mcp-gateway/README.md) - IBM ContextForge MCP gateway.
- [`ai-playground/README.md`](ai-playground/README.md) - local AI playground on an Apple Silicon Mac with minikube + krunkit, where pods get the GPU.
- [`architecture.svg`](architecture.svg) / [`architecture.png`](architecture.png) - simple AI Factory architecture visual.

The Kubernetes substrate these guides run on is documented in [`../platform/README.md`](../platform/README.md).
