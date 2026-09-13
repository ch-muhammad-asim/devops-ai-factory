# K3s vs kubeadm

The canonical comparison and research guide has moved to:

**[`../k3s-vs-kubeadm/README.md`](../k3s-vs-kubeadm/README.md)**

That guide now contains the complete material in one place, including:

- what K3s and kubeadm are;
- single-node and multi-node architecture;
- HA vs non-HA;
- embedded etcd vs external datastore/etcd;
- why multiple VMs on one physical host are not real HA;
- K3s installed natively on Linux;
- K3s using Docker as a runtime;
- K3s itself running inside Docker with `rancher/k3s`;
- k3d for K3s-in-Docker development and CI;
- container networking, storage and privileged-container security considerations;
- scenario-based recommendations for this repository.

This compatibility file remains so existing links do not break.
