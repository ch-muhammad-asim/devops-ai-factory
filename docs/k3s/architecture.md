# K3s architecture patterns

The diagrams in this document are Mermaid diagrams, so GitHub renders them as architecture images while keeping the source version-controlled and reviewable.

## 1. Single-node K3s

A single K3s server runs both control-plane components and application workloads. K3s uses an embedded SQLite datastore by default for a single-server cluster.

```mermaid
flowchart TB
    USER[Operator / CI / kubectl]
    CLIENT[Users / Clients]

    subgraph HOST[Single EC2 / Physical Server]
        API[K3s Server\nAPI server\ncontroller-manager\nscheduler\nSQLite datastore]
        NODE[kubelet + containerd + CNI]
        INGRESS[Traefik Ingress]
        APPS[Application Pods]
        SYSTEM[CoreDNS / metrics-server / platform pods]
    end

    USER -->|TCP 6443| API
    CLIENT -->|HTTP / HTTPS| INGRESS
    API --> NODE
    NODE --> APPS
    NODE --> SYSTEM
    INGRESS --> APPS
```

### Characteristics

- lowest infrastructure cost;
- easiest Kubernetes topology to operate;
- server also runs workloads;
- no control-plane HA;
- host failure takes the entire cluster offline.

### Best fit

- development and staging;
- internal services;
- small production workloads where downtime is acceptable;
- one-server deployments that genuinely need Kubernetes APIs, Helm, Ingress, Secrets, Deployments, Jobs, and related features.

## 2. Multi-node K3s without HA

One K3s server owns the control plane and datastore while one or more K3s agents run workloads.

```mermaid
flowchart TB
    USER[Operator / CI / kubectl]

    subgraph CLUSTER[K3s Cluster - Non-HA Control Plane]
        SERVER[K3s Server\nControl Plane + Datastore]
        AGENT1[K3s Agent 1\nkubelet + containerd]
        AGENT2[K3s Agent 2\nkubelet + containerd]
        AGENT3[K3s Agent 3\nkubelet + containerd]
    end

    USER -->|TCP 6443| SERVER
    SERVER --> AGENT1
    SERVER --> AGENT2
    SERVER --> AGENT3
```

### Characteristics

- workloads can be distributed across several machines;
- worker capacity can grow independently;
- the single server remains a control-plane single point of failure;
- existing workloads may continue running for a period during a control-plane outage, but scheduling, reconciliation, API operations, and cluster changes are unavailable until the server returns.

### Best fit

- dev/staging clusters with multiple workers;
- workloads requiring more compute than one node;
- environments where control-plane downtime is acceptable.

## 3. K3s HA with embedded etcd

For embedded-etcd HA, K3s requires an odd number of server nodes, with three being the normal minimum. Each server runs control-plane services and an etcd member.

```mermaid
flowchart TB
    USER[Operators / CI]
    CLIENT[Users / Clients]
    LB[Fixed Registration Address / TCP Load Balancer / VIP]

    subgraph CONTROL[K3s HA Control Plane]
        S1[Server 1\nControl Plane + etcd]
        S2[Server 2\nControl Plane + etcd]
        S3[Server 3\nControl Plane + etcd]
    end

    subgraph WORKERS[Optional K3s Agent Nodes]
        W1[Agent 1]
        W2[Agent 2]
        W3[Agent 3]
    end

    USER --> LB
    CLIENT --> LB
    LB --> S1
    LB --> S2
    LB --> S3

    S1 <-->|etcd quorum| S2
    S2 <-->|etcd quorum| S3
    S1 <-->|etcd quorum| S3

    W1 --> LB
    W2 --> LB
    W3 --> LB
```

### Quorum

With three embedded-etcd server nodes, quorum is two. The cluster can tolerate one server failure and retain control-plane availability.

The servers should run on **separate failure domains**. Three VMs on one physical machine do not provide physical-host HA.

### Best fit

- self-managed production Kubernetes where control-plane availability matters;
- small/medium clusters where a simpler operational model is preferred;
- environments where three independent servers are available.

## 4. K3s HA with an external datastore

K3s can also use an external etcd, MySQL/MariaDB, or PostgreSQL datastore. This separates datastore lifecycle from K3s server lifecycle but adds another critical distributed system to operate.

```mermaid
flowchart TB
    LB[Fixed Registration Address / Load Balancer]

    subgraph SERVERS[K3s Servers]
        S1[Server 1]
        S2[Server 2]
        S3[Server 3]
    end

    DB[(External HA Datastore\netcd / PostgreSQL / MySQL)]

    LB --> S1
    LB --> S2
    LB --> S3
    S1 --> DB
    S2 --> DB
    S3 --> DB
```

Use this topology only when there is a clear reason to manage the datastore independently. Embedded etcd is usually the simpler K3s HA starting point.

## 5. Multiple VMs on one physical server

This topology can emulate a multi-node cluster, but it is **not true HA** because every VM shares the same physical failure domain.

```mermaid
flowchart TB
    subgraph PHYSICAL[One Physical Server - Single Failure Domain]
        subgraph VMS[Virtual Machines]
            S1[VM 1 - K3s Server]
            S2[VM 2 - K3s Server]
            S3[VM 3 - K3s Server]
            W1[VM 4 - K3s Agent]
            W2[VM 5 - K3s Agent]
            W3[VM 6 - K3s Agent]
        end
    end

    FAILURE[Physical host failure]
    PHYSICAL --> FAILURE
    FAILURE --> DOWN[All control-plane and worker VMs unavailable]
```

### Appropriate use

- learning K3s HA mechanics;
- CKA/CKS-style labs;
- testing cluster automation;
- validating etcd quorum and node-join procedures.

### Not appropriate as

- production HA;
- host-failure resilience;
- availability-zone resilience.

## 6. Production failure-domain model

A genuine HA design places control-plane nodes on separate physical hosts or availability zones.

```mermaid
flowchart LR
    LB[API Load Balancer / Fixed Address]

    subgraph AZ1[Failure Domain / AZ 1]
        S1[K3s Server 1]
        W1[Worker 1]
    end

    subgraph AZ2[Failure Domain / AZ 2]
        S2[K3s Server 2]
        W2[Worker 2]
    end

    subgraph AZ3[Failure Domain / AZ 3]
        S3[K3s Server 3]
        W3[Worker 3]
    end

    LB --> S1
    LB --> S2
    LB --> S3
    S1 <-->|etcd| S2
    S2 <-->|etcd| S3
    S1 <-->|etcd| S3
```

The repository currently deploys the single-node profile. Moving to HA should create multiple independent EC2 instances and distribute them across failure domains; creating several VMs on the same EC2 instance would not satisfy the HA objective.

## Sources

- https://docs.k3s.io/architecture
- https://docs.k3s.io/datastore/ha-embedded
- https://docs.k3s.io/datastore/ha
- https://docs.k3s.io/datastore/cluster-loadbalancer
