# Kubernetes platform comparison

This directory is the **comparison hub** for the Kubernetes options evaluated by this repository.

It brings the important choices into one place so an engineer can quickly answer:

- Which options are Kubernetes distributions and which are supporting tools?
- Which option is best for a single server?
- Which option is best for a small self-hosted HA cluster?
- Which option is strongest for security/compliance?
- Which option is best for immutable infrastructure?
- When should kubeadm be preferred over a packaged distribution?
- When should Kubernetes be avoided entirely in favor of Docker Compose or Podman Compose?

The detailed K3s-vs-kubeadm research remains under [`../k3s-vs-kubeadm/`](../k3s-vs-kubeadm/). This README is the higher-level comparison across the full platform landscape.

> Research review: 2026-09-09. The recommendations are intended for self-hosted Kubernetes on Linux, VMs, cloud instances, and bare metal.

---

## Executive recommendation

For the architecture represented by this repository:

| Requirement | Recommended starting point |
|---|---|
| One server only needs containers | **Docker Compose / Podman Compose** |
| One server needs Kubernetes | **K3s** |
| Small self-hosted multi-node cluster, non-HA | **K3s** |
| Small/medium self-hosted HA cluster | **K3s with 3 server nodes + embedded etcd** |
| Security/compliance-focused self-hosted Kubernetes | **RKE2** |
| Greenfield immutable Kubernetes appliances | **Talos Linux** |
| Existing upstream kubeadm operating standard | **kubeadm** |
| Lightweight alternative to K3s | **k0s** |
| Ubuntu/Canonical-centered environment | **MicroK8s** |
| Local/CI multi-node Kubernetes in Docker | **k3d** |

For this repository, **K3s remains the default choice** because it gives the best balance of operational simplicity, low overhead, standard Kubernetes APIs, and a clean evolution path from one node to a real three-server HA cluster.

---

# 1. First understand what each project actually is

Not every project in this comparison has the same job.

```text
Kubernetes distributions
├── K3s
├── RKE2
├── k0s
└── MicroK8s

Kubernetes-focused operating system
└── Talos Linux

Upstream Kubernetes bootstrap/join tool
└── kubeadm

K3s-in-Docker local/CI tool
└── k3d

Not Kubernetes
├── Docker Compose
└── Podman Compose
```

This distinction matters. Choosing a Kubernetes distribution is different from choosing a node operating system, a bootstrap mechanism, or a development tool.

---

# 2. Full comparison matrix

| Area | K3s | RKE2 | Talos Linux | k0s | MicroK8s | kubeadm | k3d |
|---|---|---|---|---|---|---|---|
| Primary role | Lightweight Kubernetes distribution | Security/compliance-oriented Kubernetes distribution | Immutable Kubernetes-focused OS | Lightweight Kubernetes distribution | Canonical Kubernetes distribution | Kubernetes bootstrap/join tool | K3s-in-Docker dev/CI tool |
| Open source | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Best fit | Small/medium self-hosted, edge, simple HA | Enterprise/security-sensitive self-hosted | Dedicated immutable Kubernetes nodes | Lightweight alternative | Ubuntu/Canonical environments | Teams wanting explicit upstream assembly | Local development and CI |
| Single-node experience | **Excellent** | Good | Good after Talos learning curve | Very good | Very good | Works, more setup | Excellent for disposable local clusters |
| Small resource footprint | **Excellent** | Moderate | Very small OS footprint | Excellent | Good | Depends on chosen components | Host-dependent |
| Bundled runtime | containerd | containerd | containerd as part of Talos/Kubernetes node design | packaged runtime model | packaged runtime model | Runtime prepared separately | K3s/containerd inside Docker nodes |
| Networking defaults | Packaged sensible defaults | More enterprise/upstream-oriented defaults | Declarative machine + cluster config | Packaged defaults | Packaged add-ons | CNI installed separately | K3s defaults inside Docker network |
| HA control plane | 3+ K3s servers | 3+ RKE2 servers | Kubernetes HA on Talos nodes | Supported | Automatic HA model at 3+ nodes | Stacked or external etcd | HA topology simulation on one Docker host |
| Default/typical HA datastore | embedded etcd | embedded etcd | etcd | etcd-oriented Kubernetes architecture | dqlite in MicroK8s HA model | stacked etcd or external etcd | K3s datastore inside containers |
| Operational simplicity | **High** | High | High after adopting Talos model | High | High | Lower; more operator ownership | Very high for dev/test |
| Traditional SSH/Linux administration | Yes | Yes | **No traditional mutable-server workflow** | Yes | Yes | Yes | Docker-host workflow |
| Security/compliance focus | Good | **Excellent** | **Excellent immutable/minimal model** | Good | Good | Depends on your implementation | Not a production security architecture |
| CIS/FIPS-oriented story | Available hardening patterns | **Strong reason to choose RKE2** | Strong secure-by-default model | Varies by deployment | Varies by deployment | You design/own it | Not the purpose |
| Deep component customization | Good | Very good | Declarative but intentionally constrained OS | Good | Good | **Excellent** | Limited to local K3s configuration |
| CKA/kubeadm learning value | Good Kubernetes practice | Good Kubernetes practice | Different OS operations model | Good Kubernetes practice | Good Kubernetes practice | **Best for kubeadm mechanics** | Good app/Helm testing, not bare-metal ops |
| Production self-hosted recommendation | **Yes** | **Yes** | **Yes** | Yes | Yes | Yes with skilled operations | No as the primary HA design |

---

# 3. Comparison by deployment size

## One physical server, only a few containers

Do **not** automatically choose Kubernetes.

If the requirement is simply:

- run several containers;
- restart them automatically;
- mount volumes;
- expose ports;
- configure environment variables;
- use a reverse proxy;

then start with:

```text
Docker Compose / Podman Compose
```

This is usually simpler than adding a Kubernetes control plane.

Use Kubernetes when you actually need Kubernetes capabilities such as Deployments, Services, Ingress, Helm, Jobs, CronJobs, ConfigMaps, Secrets, GitOps, or a future multi-node path.

## One physical server, Kubernetes required

**Recommendation: K3s.**

Why:

- complete Kubernetes cluster from one K3s server;
- bundled containerd;
- simpler networking/bootstrap defaults;
- lower operational overhead;
- server node can run workloads by default;
- easier future path to additional agents or HA servers.

kubeadm also works on one node, but it exposes more assembly and lifecycle work than most one-server deployments need.

## Multiple servers, one control plane, non-HA

**Recommendation: K3s for most small environments.**

```text
K3s server
control plane + datastore
        |
        +-- agent 1
        +-- agent 2
        +-- agent 3
```

This gives workload scale, but the single control plane is still a single point of failure.

## Multiple independent servers, real HA

**Recommendation for this repository: 3 K3s servers with embedded etcd.**

```text
                    stable API / registration endpoint
                                |
                  +-------------+-------------+
                  |             |             |
             K3s server 1  K3s server 2  K3s server 3
             CP + etcd      CP + etcd      CP + etcd
                  |             |             |
                  +-------- etcd quorum -------+
                                |
                      optional agent nodes
```

Three servers provide a quorum of two, so one server can fail without losing the control plane.

For real HA, those nodes must be in **independent failure domains**. Three VMs on one physical server are useful for testing but do not provide physical-host HA.

---

# 4. K3s

## What it is

K3s is a lightweight, conformant Kubernetes distribution designed to reduce installation and operational complexity.

The normal native architecture is:

```text
Linux
└── K3s
    ├── Kubernetes control plane (server nodes)
    ├── kubelet
    ├── containerd
    ├── networking
    └── workload Pods
```

## Strengths

- very easy single-node Kubernetes;
- strong fit for self-hosted and edge environments;
- embedded containerd;
- simple server/agent model;
- embedded-etcd HA is straightforward;
- small teams can operate it without assembling every Kubernetes component independently;
- native K3s servers can run both control-plane components and application workloads.

## Weaknesses / trade-offs

- more opinionated than kubeadm;
- some teams may prefer an enterprise/security-focused distribution such as RKE2;
- organizations already standardized on kubeadm may not want a different lifecycle model.

## Best use

**Default choice for this repository and most small-to-medium self-hosted clusters.**

---

# 5. RKE2

## What it is

RKE2 is Rancher/SUSE's enterprise-oriented Kubernetes distribution. It is closely related operationally to the K3s ecosystem but is designed with stronger datacenter/security/compliance goals.

## Strengths

- fully conformant Kubernetes;
- embedded containerd;
- strong CIS hardening story;
- FIPS-oriented support path;
- familiar server/agent HA model;
- strong choice when Rancher/SUSE ecosystem integration matters;
- better fit than K3s when regulatory/security controls are a first-class architecture requirement.

## Trade-offs

- heavier than K3s;
- more than a small lab or tiny edge server normally needs;
- the extra security/compliance emphasis may not provide value for a simple low-cost cluster.

## Best use

```text
Production-critical
+ security requirements
+ compliance requirements
+ enterprise operating model
= RKE2 is a very strong choice
```

If this repository later becomes a regulated enterprise platform, **RKE2 is the first distribution I would re-evaluate against K3s**.

---

# 6. Talos Linux

## What it is

Talos Linux is not merely another Kubernetes installer. It is an immutable, API-managed Linux operating system designed specifically to run Kubernetes.

Traditional model:

```text
Ubuntu / Debian / RHEL
        |
package manager + SSH + systemd administration
        |
Kubernetes distribution
```

Talos model:

```text
Talos Linux
        |
declarative machine configuration / API
        |
Kubernetes
```

## Strengths

- immutable infrastructure approach;
- minimal OS surface;
- no normal SSH-based mutable-server workflow;
- excellent fit for rebuild-over-repair operations;
- attractive for dedicated bare-metal Kubernetes appliances;
- security-focused by reducing unnecessary packages and mutable host state.

## Trade-offs

- changes how SREs operate Linux nodes;
- traditional SSH, package-manager, and ad-hoc host repair habits do not map directly;
- requires the team to learn the Talos management model.

## Best use

**Greenfield dedicated Kubernetes infrastructure where immutable, API-managed nodes are a deliberate design goal.**

For brand-new bare-metal infrastructure, Talos is one of the strongest alternatives to K3s/RKE2.

---

# 7. k0s

## What it is

k0s is a lightweight, low-dependency Kubernetes distribution designed around an all-inclusive/single-binary operating model.

## Strengths

- lightweight deployment;
- few host dependencies;
- works across cloud, bare metal, edge, and similar environments;
- simple alternative to more manually assembled Kubernetes.

## Trade-offs

For the goals of this repository, it overlaps heavily with K3s. K3s already solves the lightweight/simple-cluster requirement, while RKE2 and Talos each provide a clearer reason to change architecture.

## Best use

Choose k0s when your team specifically prefers its packaging/management model or already operates it successfully.

---

# 8. MicroK8s

## What it is

MicroK8s is Canonical's packaged Kubernetes distribution, especially natural in Ubuntu/Canonical-centered environments.

## Strengths

- simple installation;
- convenient add-ons;
- straightforward clustering;
- automatic HA behavior in its supported multi-node model;
- strong fit where Ubuntu and Snap are already platform standards.

## Trade-offs

- Snap becomes part of the lifecycle/operations model;
- its HA datastore model differs from the embedded-etcd approach used by K3s/RKE2;
- less compelling for this repository because, although the nodes run Ubuntu 26.04 LTS, the current design keeps Kubernetes lifecycle out of snap and Canonical-specific tooling.

## Best use

**Ubuntu/Canonical-standardized infrastructure where MicroK8s lifecycle conventions are already accepted.**

---

# 9. kubeadm

## What it is

kubeadm is an upstream Kubernetes bootstrap and node-join tool. It is not a complete packaged Kubernetes distribution in the same sense as K3s, RKE2, k0s, or MicroK8s.

With kubeadm, the operator owns more of the surrounding architecture:

```text
Linux
├── CRI runtime
├── kubelet
├── kubeadm
├── CNI selection/installation
├── control-plane endpoint
├── Kubernetes control plane
└── etcd topology
```

## Strengths

- closest to an explicit upstream Kubernetes bootstrap model;
- excellent for learning kubeadm mechanics;
- maximum control over runtime, CNI, PKI/bootstrap, control-plane flags, and etcd topology;
- strong fit when an organization already has mature kubeadm automation and runbooks.

## Trade-offs

- more moving parts to assemble and maintain;
- greater operational burden for small teams;
- does not automatically become a better choice just because the cluster is production or multi-node.

## Best use

Choose kubeadm when **explicit upstream bootstrap ownership is itself a requirement**.

---

# 10. k3d

## What it is

k3d runs K3s nodes inside Docker containers and is designed for local development, CI, and disposable test clusters.

```text
Developer/CI host
└── Docker
    ├── k3d load-balancer
    ├── K3s server container(s)
    └── K3s agent container(s)
```

## Strengths

- very fast cluster creation/deletion;
- good for Helm tests and integration tests;
- easy multi-node topology simulation;
- excellent developer experience.

## Important limitation

Three K3s server containers on one laptop are **not real HA**. They share one physical host/failure domain.

## Best use

**Local development and CI, not the primary production HA architecture.**

---

# 11. Security and compliance comparison

| Requirement | Best fit | Why |
|---|---|---|
| Basic secure self-hosting | K3s | Simple system with fewer operational layers |
| CIS/FIPS/regulatory focus | **RKE2** | Security/compliance is a primary design goal |
| Minimal immutable node OS | **Talos Linux** | Dedicated Kubernetes OS with API-managed immutable approach |
| Full custom hardening ownership | kubeadm | Operator controls the entire assembly, but also owns the burden |
| Local dev isolation | k3d | Convenient disposable testing; not a production security boundary |

Security is not only a distribution choice. A production design must still address:

- RBAC;
- secrets management;
- network policy;
- image scanning/signing policy;
- host and kernel patching where applicable;
- etcd/data encryption decisions;
- backup security;
- TLS/certificate lifecycle;
- ingress exposure;
- audit logging;
- monitoring and incident response.

---

# 12. HA comparison

| Platform | Typical small HA approach | Main operational characteristic |
|---|---|---|
| **K3s** | 3 server nodes + embedded etcd | Simple and compact |
| **RKE2** | 3 server nodes + embedded etcd | Enterprise/security-oriented K3s-family model |
| **Talos Linux** | 3+ Talos control-plane nodes + etcd | Immutable/API-managed nodes |
| **k0s** | Multi-controller HA Kubernetes | Lightweight distribution model |
| **MicroK8s** | 3+ node HA model using its packaged datastore approach | Very convenient in Canonical environments |
| **kubeadm** | 3 control planes with stacked etcd, or separate external etcd | Maximum explicit operator control |
| **k3d** | Multiple server containers | Lab topology only if all containers share one host |

The core HA rule applies to every option:

> **HA requires independent failure domains, not merely multiple Kubernetes node names.**

Three VMs, containers, or processes on one physical host do not protect against failure of that physical host.

---

# 13. Operational complexity

A simplified spectrum for this repository's use cases:

```text
Less platform assembly

k3d (dev/test)
  |
K3s
  |
k0s / MicroK8s
  |
RKE2
  |
Talos (simple after adopting its model, but a different OS workflow)
  |
kubeadm

More explicit platform assembly / operator ownership
```

This is not a quality ranking. More control can be desirable, but it also creates more lifecycle responsibility.

---

# 14. Self-hosted recommendation by scenario

## Scenario A — home lab / small private cluster

Use **K3s**.

If only containers are needed, use Compose instead.

## Scenario B — small company production cluster

Use **K3s with three independent server nodes**, embedded etcd, a stable API endpoint, SSD/NVMe storage, and tested snapshots/restores.

## Scenario C — regulated/security-sensitive company

Evaluate **RKE2** first.

## Scenario D — greenfield bare-metal Kubernetes appliances

Evaluate **Talos Linux** seriously.

## Scenario E — enterprise already standardized on kubeadm

Stay with **kubeadm** unless there is a strong reason to change.

## Scenario F — Ubuntu-only operations standard

Evaluate **MicroK8s**.

## Scenario G — developer laptop / CI

Use **k3d**.

---

# 15. Recommendation for this repository

The current repository architecture is:

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

The design deliberately separates:

- networking;
- compute;
- Kubernetes distribution lifecycle;
- Kubernetes add-ons.

That makes K3s a particularly clean fit.

Recommended production evolution:

```text
Stage 1
1 K3s server

      |
      v

Stage 2
3 independent K3s servers
embedded etcd
servers may also run workloads

      |
      v

Stage 3
3 dedicated K3s servers
+ N K3s agents

      |
      v

Stage 4
multiple failure domains
stable API/LB
observability
GitOps
centralized secrets
scheduled etcd snapshots
periodic restore tests
```

Do not move from K3s merely because another distribution sounds more "enterprise". Change only when the requirement changes:

```text
Need more security/compliance? -> evaluate RKE2
Need immutable Kubernetes-only nodes? -> evaluate Talos
Need an Ubuntu/Canonical standard? -> evaluate MicroK8s
Need explicit upstream bootstrap ownership? -> kubeadm
Need local disposable clusters? -> k3d
Otherwise -> K3s remains the practical default
```

---

# 16. Quick decision tree

```text
Do you need Kubernetes?
|
+-- No --> Docker Compose / Podman Compose
|
+-- Yes
    |
    +-- Local development / CI?
    |   |
    |   +-- Yes --> k3d
    |
    +-- Dedicated immutable Kubernetes nodes desired?
    |   |
    |   +-- Yes --> Talos Linux
    |
    +-- Security/compliance/CIS/FIPS is the primary driver?
    |   |
    |   +-- Yes --> RKE2
    |
    +-- Existing Ubuntu/Canonical standard?
    |   |
    |   +-- Yes --> consider MicroK8s
    |
    +-- Existing kubeadm/upstream bootstrap standard?
    |   |
    |   +-- Yes --> kubeadm
    |
    +-- Otherwise --> K3s
```

---

# 17. Related documentation

For deeper technical detail, continue with:

- [`../k3s-vs-kubeadm/README.md`](../k3s-vs-kubeadm/README.md) — K3s vs kubeadm architecture, K3s-in-Docker, k3d, HA, networking, storage, and self-hosted recommendations.
- [`../k3s-vs-kubeadm/open-source-kubernetes-landscape.md`](../k3s-vs-kubeadm/open-source-kubernetes-landscape.md) — open-source classification and licensing/role distinctions.
- [`../k3s/architecture.md`](../k3s/architecture.md) — topology diagrams for K3s single-node, multi-node, HA, and lab designs.
- [`../diagrams/k3s-platform-overview.svg`](../diagrams/k3s-platform-overview.svg) — AWS/K3s architecture for this repository.

---

# Official upstream references

## K3s

- https://docs.k3s.io/
- https://docs.k3s.io/architecture
- https://docs.k3s.io/datastore/ha-embedded
- https://docs.k3s.io/installation/requirements

## RKE2

- https://docs.rke2.io/
- https://docs.rke2.io/install/ha
- https://docs.rke2.io/security/hardening_guide
- https://docs.rke2.io/security/fips_support

## Talos Linux

- https://docs.siderolabs.com/talos/

## k0s

- https://docs.k0sproject.io/

## MicroK8s

- https://canonical.com/microk8s/docs
- https://canonical.com/microk8s/docs/high-availability

## kubeadm

- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/

## k3d

- https://k3d.io/

---

## Bottom line

For this repository:

> **K3s is the best default. RKE2 is the strongest security/compliance alternative. Talos Linux is the strongest immutable-node alternative. kubeadm is best when explicit upstream bootstrap ownership is required.**

That is the comparison standard this repository uses when evaluating future Kubernetes platform changes.
