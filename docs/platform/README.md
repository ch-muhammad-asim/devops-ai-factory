# AWS EC2 K3s Platform with Terragrunt

This is the deployment guide for the Kubernetes substrate of the [AI Factory](../../README.md). All paths below are relative to the repository root.

A version-pinned K3s platform on AWS where **Terragrunt is the only deployment/orchestration interface**. Terraform remains the execution engine underneath Terragrunt, and the HashiCorp Helm provider manages Kubernetes add-ons declaratively.

There is no Makefile, no platform install/uninstall shell wrapper, and no requirement to run Helm CLI commands to build the platform.

## Architecture

![K3s on AWS platform architecture](../diagrams/k3s-platform-overview.svg)

```text
Terragrunt DAG

VPC
 |
 v
EC2
 |
 v
K3s
 |
 v
Traefik
 |
 v
cert-manager
 |
 v
Argo CD
```

Every box is an independent Terragrunt unit with its own Terraform state. Terragrunt dependency blocks define the order.

- `vpc` owns AWS networking.
- `ec2` owns EC2, EIP, IAM/SSM, security groups and EBS. EC2 instances and their EIPs are created from a map with Terraform `for_each` so additional nodes have stable key-based resource addresses. It also renders the node bootstrap and delivers it as EC2 user data.
- `k3s` retrieves the resulting kubeconfig onto the machine running Terragrunt and exposes the client material to the Helm units. It does not install anything itself.
- `traefik`, `cert-manager` and `argocd` use a reusable Terraform `helm_release` module, but are planned/applied/destroyed through Terragrunt.
- K3s is installed by cloud-init on first boot, so there is no Run Command association to converge and no SSH access anywhere in the workflow. Downstream Terragrunt units consume the K3s unit's outputs, so no kubeconfig bootstrap step is required for deployment.

The current compute profile is a single EC2 K3s server/worker. It is intentionally non-HA; the module/state boundaries and map-driven EC2 model allow later evolution toward multi-node HA.

## Repository layout

```text
.
├── README.md                      # AI Factory guide (main entry point)
├── VERSIONS.md
├── docs/
│   ├── README.md                  # documentation index
│   ├── platform/README.md         # this file: K3s platform deployment
│   ├── ai-factory/                # inference, LLM gateway, LLMKube, MCP gateway guides
│   ├── terragrunt-workflow/README.md
│   ├── diagrams/
│   ├── k3s/
│   ├── k3s-vs-kubeadm/
│   └── kubernetes-platform-comparison/
├── infrastructure/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ec2/
│   │   ├── k3s/
│   │   └── helm-release/
│   ├── templates/
│   │   └── k3s-install.sh.tftpl
│   └── live/
│       ├── root.hcl
│       ├── _common/
│       │   ├── vpc.hcl
│       │   ├── ec2.hcl
│       │   ├── k3s.hcl
│       │   ├── traefik.hcl
│       │   ├── cert-manager.hcl
│       │   └── argocd.hcl
│       └── dev/us-east-1/
│           ├── vpc/terragrunt.hcl
│           ├── ec2/terragrunt.hcl
│           ├── k3s/terragrunt.hcl
│           ├── traefik/terragrunt.hcl
│           ├── cert-manager/terragrunt.hcl
│           └── argocd/terragrunt.hcl
└── kubernetes/helm/
    ├── traefik/values.yaml
    ├── cert-manager/values.yaml
    └── argocd/values.yaml
```

## Prerequisites

Required for deployment:

- Terragrunt `1.x`
- Terraform `>= 1.10.0` as the Terragrunt execution engine (S3 native state locking via `use_lockfile` needs 1.10+)
- AWS CLI v2, `bash` and `curl` on the machine running Terragrunt: the `k3s` unit fetches the kubeconfig with `aws ssm send-command`, and the `ec2` unit discovers the operator IP with `curl` unless `TG_OPERATOR_CIDR` is set
- AWS credentials with the permissions required by the stack, including `ssm:SendCommand` and `ssm:GetCommandInvocation` against the node
- network access to Terraform/Helm provider registries and upstream Helm chart repositories

`kubectl` is optional for post-deployment validation. The Helm CLI is not required for normal deployment.

## Pinned versions

- K3s `v1.36.4+k3s1`
- HashiCorp Helm provider `3.2.0`
- Traefik Helm chart `41.4.0`
- Traefik Proxy `v3.7.12`
- cert-manager chart/application `v1.21.1`
- Argo CD Helm chart `10.8.1`
- Argo CD application `v3.5.2`

See [`VERSIONS.md`](../../VERSIONS.md).

## Deploy with Terragrunt only

Choose the environment/region directory:

```bash
cd infrastructure/live/dev/us-east-1
```

### First run: bootstrap the remote backend

On a brand-new AWS account/region the S3 state bucket does not exist yet. A plain `terragrunt run --all init` will fail with `NoSuchBucket`; the first initialization must explicitly allow Terragrunt to bootstrap the backend:

```bash
terragrunt run --all --backend-bootstrap init
```

Terragrunt first prints the dependency graph and, when the state bucket is missing, prompts for confirmation before creating it. A typical first-run interaction is:

```text
Remote state S3 bucket <generated-state-bucket> does not exist or is not accessible.
Would you like Terragrunt to create it? (y/n) y
```

Answer `y` only when you intentionally expect Terragrunt to create the backend in the active AWS account/region.

After confirmation, Terragrunt initializes each unit in dependency order:

```text
vpc -> ec2 -> k3s -> traefik -> cert-manager -> argocd
```

On a completely fresh stack you may see warnings similar to:

```text
Config .../vpc/terragrunt.hcl is a dependency of .../ec2/terragrunt.hcl
that has no outputs, but mock outputs were provided.
```

That is expected during `init` and fresh-stack planning. The dependency does not have real Terraform outputs yet because nothing has been applied, so the leaf configuration uses its declared mock outputs for commands where mocks are explicitly allowed.

A successful `init` means the remote backend has been created/configured and Terraform providers/modules have been initialized. **It does not create the VPC, EC2 instance, K3s cluster, or Helm releases.** Infrastructure creation starts with `apply`.

No manual `aws s3` command, Makefile target, direct Terraform command, or pre-created bucket is required.

### Plan and apply

After initialization:

```bash
terragrunt run --all plan
terragrunt run --all apply
```

Terragrunt applies dependencies in order:

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

After the first successful deployment, repeat:

```bash
terragrunt run --all plan
```

At that point the dependency outputs are real and the Helm units can refresh against the live K3s API instead of using fresh-stack mocks.

For later reinitialization, after the backend already exists, the normal command is sufficient:

```bash
terragrunt run --all init
```

If you prefer explicit backend lifecycle management instead of the one-command first run, this equivalent Terragrunt-only sequence is also valid:

```bash
cd vpc
terragrunt backend bootstrap
cd ..
terragrunt run --all init
```

## EC2 nodes use `for_each`

The EC2 module does not use a singleton resource or `count`. It creates EC2 instances, EIPs and EIP associations from the `instances` map using Terraform `for_each`.

The current default intentionally contains one node:

```hcl
instances = {
  primary = {}
}
```

The key becomes the stable Terraform resource address, for example:

```text
aws_instance.this["primary"]
aws_eip.this["primary"]
aws_eip_association.this["primary"]
```

Additional compute can be declared without changing the resource model:

```hcl
instances = {
  primary = {}

  worker-1 = {
    name          = "k3s-dev-us-east-1-worker-1"
    instance_type = "t3.medium"
  }

  worker-2 = {
    name          = "k3s-dev-us-east-1-worker-2"
    instance_type = "t3.medium"
  }
}
```

Per-node `name`, `instance_type`, `subnet_id`, `root_volume_size` and `tags` may be overridden; omitted values inherit the module defaults.

The current K3s unit still consumes the singular outputs for `primary_instance_key = "primary"`, so **adding more EC2 map entries only creates compute; it does not yet join those additional machines to K3s**. Multi-server/agent K3s bootstrap should be implemented as a separate cluster-topology change rather than silently turning extra EC2 instances into cluster members.

For environments that already created the old singleton EC2/EIP resources, Terraform `moved` blocks migrate the existing state addresses to the `"primary"` `for_each` addresses. Review `terragrunt plan` before applying: the expected result is an address move, not EC2/EIP replacement, when no other settings changed.

## Node public addressing

The node runs in a public subnet and there is no NAT gateway, so it needs a public address at launch for the user-data bootstrap to reach the internet. The subnet also sets `map_public_ip_on_launch`, so the module default matches it:

```hcl
associate_public_ip_address = true
```

Keep this aligned with the subnet. If the module requests `false` while the subnet assigns one anyway, the attribute never converges and every `terragrunt plan` reports an EC2 replacement even when nothing else changed. The Elastic IP is associated immediately afterwards and remains the stable endpoint.

## Deletion protection

EC2 API termination protection and stop protection are enabled through Terragrunt in `infrastructure/live/_common/ec2.hcl`:

```hcl
enable_termination_protection = true
enable_stop_protection        = true
```

They are ordinary managed attributes, so clearing them in the console produces drift that the next `terragrunt plan` reports and `terragrunt apply` corrects. Never set them with `aws ec2 modify-instance-attribute`.

Both attributes propagate slowly. A read taken seconds after `apply` can still report `false` and settles about a minute later, so re-read before concluding that an apply failed.

While protection is on, AWS refuses to replace or terminate the node. Any run that needs to do so must clear it first, apply, and then re-enable it:

```bash
cd infrastructure/live/dev/us-east-1/ec2
TF_VAR_enable_termination_protection=false TF_VAR_enable_stop_protection=false terragrunt apply
```

This applies to a node replacement triggered by editing the user-data bootstrap, as well as to `destroy`.

## Work on one component

Each lifecycle can still be reviewed independently:

```bash
cd infrastructure/live/dev/us-east-1/ec2
terragrunt plan
terragrunt apply
```

Examples:

```bash
cd ../k3s && terragrunt plan
cd ../traefik && terragrunt plan
cd ../cert-manager && terragrunt plan
cd ../argocd && terragrunt plan
```

Do not call Terraform directly; Terragrunt supplies the parent configuration, remote state, provider generation, shared inputs and dependencies.

## Kubernetes API access

The API defaults to the current operator public `/32`. Override it before planning/applying when office/VPN access is required:

```bash
export TG_OPERATOR_CIDR="203.0.113.0/24"
```

## Node bootstrap through EC2 user data

K3s is installed by the script at `infrastructure/templates/k3s-install.sh.tftpl`, rendered by Terragrunt and delivered as EC2 user data. The node converges during first boot with no Systems Manager association, no SSH, and no operator-side provisioning step.

The Elastic IP is allocated before the instance and published to the node as the `PublicIp` instance tag, so the script reads it from IMDSv2 instance tags and adds it to the API server TLS SAN list. It deliberately does not rely on `public-ipv4`, which reports the launch-time address until the EIP association completes. It then writes an operator-facing kubeconfig to `/etc/rancher/k3s/k3s-public.yaml` with the public endpoint already substituted.

The bootstrap log is available on the node at `/var/log/k3s-bootstrap.log`, and also in `/var/log/cloud-init-output.log`.

Because `user_data_replace_on_change` is enabled, editing the template replaces the node rather than leaving a running instance that no longer matches the committed bootstrap. See the deletion protection section below before making that change.

## Kubeconfig on your local machine

The K3s unit fetches the kubeconfig during `apply` using a `local-exec` provisioner, which reads the file off the node through Systems Manager. No manual copy step is required.

By default it is written to `~/.kube/<cluster_name>.yaml` with mode `600`. Override the destination with the `kubeconfig_path` input.

```bash
cd infrastructure/live/dev/us-east-1/k3s
terragrunt output kubeconfig_path
```

The same content is available as a sensitive output:

```bash
terragrunt output -raw kubeconfig
```

Optional verification:

```bash
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml
kubectl get nodes -o wide
kubectl get pods -A
```

The kubeconfig holds cluster-admin credentials. It is written outside the repository, and the file plus the remote Terraform state must both be treated as sensitive. Access to the S3 state bucket must be tightly controlled.

Retrieving the kubeconfig requires the AWS CLI plus `ssm:SendCommand` and `ssm:GetCommandInvocation` against the node from wherever Terragrunt runs.

## Platform add-ons

No `helm install` or shell installer is used. Terragrunt drives the reusable `infrastructure/modules/helm-release` module, which uses HashiCorp Helm provider `3.2.0`.

The source values remain reviewable under `kubernetes/helm/*/values.yaml`, while chart identity/version live in `infrastructure/live/_common/*.hcl`.

Apply an individual release with Terragrunt:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt plan
terragrunt apply
```

The same pattern applies to `cert-manager` and `argocd`.

## Outputs

From any unit:

```bash
terragrunt output
```

Across the region stack:

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all output
```

## Destroy

Deletion protection must be cleared before the EC2 node can be destroyed, otherwise the run fails on the `ec2` unit:

```bash
cd infrastructure/live/dev/us-east-1/ec2
TF_VAR_enable_termination_protection=false TF_VAR_enable_stop_protection=false terragrunt apply
```

Then destroy the whole graph through Terragrunt:

```bash
cd infrastructure/live/dev/us-east-1
terragrunt run --all destroy
```

Terragrunt uses the dependency graph to destroy dependents before dependencies.

The local kubeconfig is not managed by Terraform and is left behind. Remove it separately:

```bash
rm -f ~/.kube/k3s-dev-us-east-1.yaml
```

## Existing-state migration

Two historical layouts may require migration before applying this revision:

1. An older revision used a combined `k3s-ec2` Terraform state. Existing EC2 resources must be migrated/imported into the split EC2 state before applying the current stack.
2. An older revision installed Traefik, cert-manager and Argo CD outside Terraform state. If those Helm releases exist, import them into their Terragrunt unit states before applying:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt import helm_release.this traefik/traefik

cd ../cert-manager
terragrunt import helm_release.this cert-manager/cert-manager

cd ../argocd
terragrunt import helm_release.this argocd/argocd
```

Always review `terragrunt plan` after import because this revision manages the official upstream charts directly instead of local wrapper charts.

## Security notes

- Kubernetes API `6443` is restricted to `TG_OPERATOR_CIDR`.
- SSH `22` is not exposed; the node uses AWS Systems Manager.
- IMDSv2 is required.
- The node holds a public IP because the subnet has no NAT gateway; inbound access is restricted by security group rules, not by private addressing.
- EBS is encrypted.
- K3s kubeconfig credentials live in sensitive Terraform state and in the local kubeconfig file, which is written with mode `600` outside the repository.
- EC2 API termination and stop protection are enabled.
- Traefik dashboard is not public by default.
- Never commit kubeconfig, Terraform state, cloud credentials, Cloudflare tokens or private keys.

For the detailed command model and state/dependency explanation, see [`docs/terragrunt-workflow/README.md`](../terragrunt-workflow/README.md).
