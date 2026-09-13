# Open-source Kubernetes landscape

This document clarifies an important terminology point in the Kubernetes ecosystem: several projects can all be **open source** while still playing very different roles.

> **Research review:** 2026-09-09. Project type and licensing notes were checked against the upstream project repositories and documentation.

## Short answer

Yes: **K3s, RKE2, k0s, MicroK8s, Talos Linux, kubeadm, and k3d are all open-source projects**.

However, they are not all Kubernetes distributions in the same sense.

```text
Open-source Kubernetes distributions
├── K3s
├── RKE2
├── k0s
└── MicroK8s

Open-source Kubernetes-focused operating system
└── Talos Linux

Open-source Kubernetes bootstrap tool
└── kubeadm

Open-source K3s-in-Docker development / CI tool
└── k3d
```

The distinction matters because choosing a Kubernetes distribution, choosing the node operating system, choosing a bootstrap tool, and choosing a local development tool are different architecture decisions.

---

## Classification and licenses

| Project | Open source? | Primary role | Main project license | Practical meaning |
|---|---:|---|---|---|
| **K3s** | Yes | Kubernetes distribution | Apache-2.0 | Lightweight, packaged Kubernetes for edge, single-node, and self-hosted clusters |
| **RKE2** | Yes | Kubernetes distribution | Apache-2.0 | Security/compliance-focused Rancher/SUSE Kubernetes distribution |
| **k0s** | Yes | Kubernetes distribution | Apache-2.0 for software code; project docs have separate CC BY-SA terms | Single-binary, low-dependency Kubernetes distribution |
| **MicroK8s** | Yes | Kubernetes distribution | Apache-2.0 | Canonical/Ubuntu-oriented packaged Kubernetes |
| **Talos Linux** | Yes | Kubernetes-focused Linux operating system | MPL-2.0 | Immutable, API-managed OS designed specifically to host Kubernetes |
| **kubeadm** | Yes | Kubernetes bootstrap/join tool | Apache-2.0 as part of Kubernetes | Initializes and joins upstream Kubernetes nodes; it is not a batteries-included distribution |
| **k3d** | Yes | Local/CI cluster tool | MIT | Runs K3s nodes as Docker containers; mainly a development/test workflow |

Open source does **not** mean every surrounding service is free. Vendors can separately sell enterprise support, management platforms, hosted services, training, or certified binaries while the underlying project remains open source.

---

# 1. What is a Kubernetes distribution?

A Kubernetes distribution packages upstream Kubernetes with additional installation, lifecycle, defaults, and integration choices so operators can deploy a usable cluster without assembling every component independently.

Conceptually:

```text
Upstream Kubernetes components
        |
        +-- API server
        +-- scheduler
        +-- controller manager
        +-- kubelet
        +-- etcd / datastore
        |
Distribution adds packaging and operating decisions
        |
        +-- installation workflow
        +-- runtime defaults
        +-- networking defaults
        +-- upgrade mechanism
        +-- datastore choices
        +-- add-ons / integrations
        +-- security defaults
```

K3s, RKE2, k0s, and MicroK8s all fit this model, although they make different trade-offs.

---

# 2. K3s

K3s is an open-source lightweight Kubernetes distribution.

It packages Kubernetes into a simpler operational model and includes common pieces such as containerd and cluster networking defaults.

Use K3s when the goal is:

- one-server Kubernetes;
- small or medium self-hosted clusters;
- three-server HA using embedded etcd;
- lower operational overhead;
- edge or resource-conscious environments;
- a standard Linux operating model without unnecessary Kubernetes assembly work.

For this repository, K3s remains the default recommendation because it offers the best balance of simplicity, Kubernetes compatibility, and a clean HA growth path.

Upstream repository: https://github.com/k3s-io/k3s

---

# 3. RKE2

RKE2 is also an open-source Kubernetes distribution.

It is closely related to the Rancher/SUSE ecosystem but targets a more security- and compliance-oriented operating model than K3s.

Use RKE2 when requirements include:

- enterprise security controls;
- CIS hardening;
- FIPS requirements;
- Rancher/SUSE integration;
- a conventional Linux server operating model;
- K3s-like deployment simplicity with stronger compliance positioning.

A useful mental model is:

```text
K3s
  -> lightweight and operationally simple

RKE2
  -> operational simplicity
  + stronger security/compliance emphasis
  + more datacenter-oriented defaults
```

Upstream repository: https://github.com/rancher/rke2

---

# 4. k0s

k0s is an open-source Kubernetes distribution designed around an all-inclusive single binary and low host dependencies.

It is a credible alternative when you want:

- a very small host footprint;
- a single-binary installation model;
- cloud, bare-metal, edge, or IoT portability;
- fewer OS dependencies.

For this repository, k0s is technically valid, but it does not currently provide a strong enough reason to replace K3s because K3s already solves the lightweight/self-hosted use case well.

License nuance: the k0s software outside its documentation directory is Apache-2.0; the repository documentation has separate Creative Commons Attribution Share Alike 4.0 terms.

Upstream repository: https://github.com/k0sproject/k0s

---

# 5. MicroK8s

MicroK8s is Canonical's open-source Kubernetes distribution.

It is particularly attractive in environments already standardized on Ubuntu and Canonical tooling.

Use MicroK8s when:

- Ubuntu is already the standard node OS;
- Snap-based lifecycle management is acceptable;
- built-in add-ons are desirable;
- simple clustering is a priority;
- dqlite-based HA fits the platform architecture.

For this Terraform/Terragrunt project, which pins Ubuntu 26.04 LTS but keeps snap out of the Kubernetes lifecycle, K3s remains a cleaner default because it does not make Snap part of the cluster operating model.

Upstream repository: https://github.com/canonical/microk8s

---

# 6. Talos Linux is different

Talos Linux is open source, but it should not be compared one-to-one with K3s as though both were simply packages installed on Ubuntu.

Talos is primarily a **specialized Linux operating system designed for Kubernetes nodes**.

Traditional K3s architecture:

```text
Physical server / VM
└── Ubuntu / Debian / Rocky / etc.
    └── systemd
        └── K3s
            └── containerd
                └── Pods
```

Talos architecture:

```text
Physical server / VM
└── Talos Linux
    └── Kubernetes
        └── containerd
            └── Pods
```

Talos emphasizes:

- immutable infrastructure;
- API-driven node management;
- minimal package surface;
- no normal SSH-first administration model;
- declarative machine configuration;
- rebuild/reconcile rather than manually repairing drift.

Talos can be an excellent greenfield choice for dedicated Kubernetes hardware, but adopting it changes the node operating model more substantially than moving from K3s to another distribution.

Upstream repository: https://github.com/siderolabs/talos

---

# 7. kubeadm is not a Kubernetes distribution

kubeadm is open source because it is part of the upstream Kubernetes project, but its role is different.

Think of it as:

```text
kubeadm
  -> initialize a control-plane node
  -> generate/bootstrap Kubernetes certificates and configuration
  -> create join workflows
  -> join control-plane and worker nodes
```

The operator still owns more of the platform around it, including:

- CRI runtime preparation;
- CNI selection and installation;
- HA load-balancer/control-plane endpoint design;
- host preparation;
- upgrade and recovery runbooks;
- many component-level choices.

Therefore:

```text
K3s / RKE2 / k0s / MicroK8s
= distributions

kubeadm
= bootstrap and lifecycle tool for upstream-style Kubernetes
```

Upstream source: https://github.com/kubernetes/kubernetes/tree/master/cmd/kubeadm

---

# 8. k3d is not a Kubernetes distribution

k3d is also open source, but it is a development and CI tool built around K3s.

It creates Docker containers that act as K3s server and agent nodes.

```text
Developer laptop / CI runner
└── Docker
    ├── k3d load balancer
    ├── K3s server container(s)
    └── K3s agent container(s)
```

Use k3d for:

- local Kubernetes development;
- Helm testing;
- CI integration tests;
- quick disposable multi-node clusters;
- testing K3s topology and etcd behavior.

Do not confuse a three-server k3d cluster on one machine with physical HA. All containers still share the same host failure domain.

Upstream repository: https://github.com/k3d-io/k3d

---

# 9. Open source vs commercial support

A project can be completely open source while commercial support is sold separately.

For example, a vendor may charge for:

- enterprise support SLAs;
- certified builds;
- management consoles;
- security/compliance assistance;
- hosted control planes;
- consulting and training;
- long-term lifecycle support.

That does not automatically make the underlying Kubernetes distribution proprietary.

When evaluating a self-hosted platform, separate these questions:

```text
1. Is the source code open?
2. What license applies?
3. Can we self-host it ourselves?
4. Is enterprise support optional or required?
5. Are some management features separate commercial products?
```

---

# 10. Practical recommendation for this repository

For the architecture represented here, focus on three serious production choices:

```text
K3s
  -> best default for small/medium self-hosted HA

RKE2
  -> better when CIS/FIPS/compliance becomes a primary requirement

Talos Linux
  -> strong greenfield choice when immutable, API-managed Kubernetes nodes are desired
```

k0s and MicroK8s remain legitimate open-source distributions, but they currently provide less architectural advantage for this specific repository.

kubeadm remains the best comparison when the goal is explicit upstream bootstrap ownership rather than a packaged distribution.

k3d remains the local/CI companion for K3s, not a production distribution replacement.

---

## Source and license references

- K3s repository and Apache-2.0 license: https://github.com/k3s-io/k3s
- RKE2 repository and Apache-2.0 license: https://github.com/rancher/rke2
- k0s repository/license: https://github.com/k0sproject/k0s
- MicroK8s repository: https://github.com/canonical/microk8s
- Talos Linux repository and MPL-2.0 license: https://github.com/siderolabs/talos
- Kubernetes/kubeadm source: https://github.com/kubernetes/kubernetes/tree/master/cmd/kubeadm
- k3d repository: https://github.com/k3d-io/k3d
