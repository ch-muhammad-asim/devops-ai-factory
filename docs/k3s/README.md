# K3s architecture and deployment guidance

This section documents the K3s topologies used or considered by this repository.

![K3s on AWS platform architecture](../diagrams/k3s-platform-overview.svg)

## Start here

For the full human-readable research and decision guide — including **K3s vs kubeadm, K3s as a Docker container, k3d, single-node, multi-node, HA/non-HA, networking, storage and security** — use [`../k3s-vs-kubeadm/README.md`](../k3s-vs-kubeadm/README.md).

For the repository deployment workflow, use [`../terragrunt-workflow/README.md`](../terragrunt-workflow/README.md).

## Repository position

This repository uses **native K3s on the EC2 Linux host**. Terragrunt owns the full lifecycle: AWS networking/compute, K3s bootstrap and the downstream Helm releases.

```text
EC2 Linux host
└── K3s service
    └── embedded containerd
        └── Kubernetes workload containers
```

K3s can also run inside Docker using the official `rancher/k3s` image, and k3d is purpose-built for K3s-in-Docker. Those modes are documented for development/CI/lab use rather than as an extra production layer around this EC2 node.

## Quick decision

| Requirement | Recommended starting point |
|---|---|
| One server, only run containers | Docker Compose / Podman Compose |
| One server, Kubernetes required | K3s |
| Local/CI Kubernetes in Docker | k3d |
| Multi-node, one control-plane server | K3s |
| Multi-node HA, small/medium self-managed platform | K3s with 3 independent server nodes and embedded etcd |
| Multi-node HA, maximum upstream bootstrap control | kubeadm |
| Several VMs/containers on one physical host | Lab/testing only; **not true HA** |

## Operational rule in this repository

Deployment changes are applied with Terragrunt. K3s is not installed manually, and Traefik/cert-manager/Argo CD are not installed with direct Helm CLI commands.

## Upstream references

- K3s architecture: https://docs.k3s.io/architecture
- K3s quick start: https://docs.k3s.io/quick-start
- K3s advanced options: https://docs.k3s.io/advanced
- K3s HA embedded etcd: https://docs.k3s.io/datastore/ha-embedded
- K3s HA external datastore: https://docs.k3s.io/datastore/ha
- Kubernetes kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- Kubernetes kubeadm HA: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
