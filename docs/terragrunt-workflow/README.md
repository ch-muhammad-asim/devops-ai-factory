# Terragrunt-only operating workflow

This repository intentionally exposes **Terragrunt as the only infrastructure/platform lifecycle CLI**.

Terraform is still the underlying engine and HashiCorp Helm provider manages Kubernetes charts, but operators do not run Terraform or Helm directly and there is no Makefile abstraction.

## Why this model

A Makefile around Terragrunt duplicates orchestration that Terragrunt already provides. The dependency graph belongs in HCL where CI and humans use the same source of truth.

```text
Terragrunt dependency graph

vpc
 |
ec2
 |
k3s
 |
traefik
 |
cert-manager
 |
argocd
```

This gives one consistent lifecycle:

```text
terragrunt init
terragrunt plan
terragrunt apply
terragrunt output
terragrunt destroy
```

and one multi-unit lifecycle:

```text
terragrunt run --all <command>
```

## First deployment

Start in the region stack:

```bash
cd infrastructure/live/dev/us-east-1
```

### Brand-new backend

If the S3 bucket configured by `root.hcl` does not exist yet, a plain:

```bash
terragrunt run --all init
```

fails with `NoSuchBucket` because Terraform cannot initialize against a backend that does not exist.

For the very first initialization, use:

```bash
terragrunt run --all --backend-bootstrap init
```

This keeps backend creation inside Terragrunt and avoids a separate AWS CLI or Terraform bootstrap project.

### What you should expect on the first run

Terragrunt first calculates the dependency graph:

```text
.
╰── vpc
    ╰── ec2
        ╰── k3s
            ├── traefik
            │   ╰── cert-manager
            │       ╰── argocd
            ├── cert-manager
            ╰── argocd
```

If the generated S3 backend bucket is missing, Terragrunt asks for confirmation before creating it:

```text
Remote state S3 bucket <generated-state-bucket> does not exist or is not accessible.
Would you like Terragrunt to create it? (y/n) y
```

Answer `y` only when the AWS account and region are the ones you intend to modify.

After that, Terragrunt initializes the units in dependency order. A successful unit normally shows Terraform messages equivalent to:

```text
Successfully configured the backend "s3"!
Initializing provider plugins...
Terraform has been successfully initialized!
```

The first run can take longer because provider plugins must be downloaded into the Terragrunt working cache.

### Expected mock-output warnings

On a fresh stack, dependency units do not have Terraform outputs yet because no infrastructure has been applied. You can therefore see warnings such as:

```text
Config .../vpc/terragrunt.hcl is a dependency of .../ec2/terragrunt.hcl
that has no outputs, but mock outputs provided and returning those in dependency output.
```

The same pattern can appear for `ec2 -> k3s` and for K3s-backed Helm units.

These warnings are **expected during fresh-stack `init`, `validate`, and planning**. The relevant dependency blocks explicitly allow mocks for those commands so Terragrunt can build and initialize the complete graph before the real resources exist.

Mocks are not the production values used after dependencies have been applied. Once the stack exists, downstream units read the real dependency outputs.

### What `init` does and does not do

After a successful first initialization:

```text
S3 remote backend     created/configured
Terraform providers   initialized/downloaded
Terragrunt DAG         resolved
VPC resources          NOT created yet
EC2 instance           NOT created yet
K3s cluster            NOT created yet
Helm releases          NOT created yet
```

`init` prepares the deployment. Actual infrastructure changes start with `apply`.

Terraform can print a message asking you to commit `.terraform.lock.hcl`. With Terragrunt, Terraform runs from generated working directories under `.terragrunt-cache`; do not commit files from that cache. Provider versions and constraints for this repository are maintained in the Terraform modules and `VERSIONS.md`.

### Plan and apply

After initialization:

```bash
terragrunt run --all plan
```

Review the plan, then deploy the complete graph:

```bash
terragrunt run --all apply
```

Terragrunt uses dependency blocks to order the deployment:

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

After the first successful apply, run another plan:

```bash
terragrunt run --all plan
```

At this point the dependencies have real state and real outputs, and the Kubernetes add-on units can refresh against the live K3s API rather than fresh-stack mocks.

### Partial apply failures are safe to resume

Each unit has its own remote Terraform state. A `run --all apply` can therefore succeed for earlier dependencies and fail later in the graph. For example, VPC and EC2 may already be created while K3s or a Helm release fails validation or deployment.

Do **not** manually delete the successful resources just because a downstream unit failed. Fix the configuration, pull the corrected revision, review the plan, and rerun:

```bash
git pull
terragrunt run --all plan
terragrunt run --all apply
```

Terragrunt/Terraform will refresh each unit. Resources already recorded in state should normally produce no changes, while the failed unit and its dependents continue from the point that still needs work.

The K3s unit exposes only the API endpoint (`kubernetes_api`) as a plain output; the CA, client certificate, client key and full kubeconfig outputs are marked sensitive. The current design reads the kubeconfig from the local file written by the Systems Manager fetch, so no `nonsensitive(...)` unwrapping is needed. An earlier revision that read the endpoint from Parameter Store did need it, because the AWS provider marks every SSM parameter value sensitive.

### Later initialization

Once the backend already exists, normal initialization is enough:

```bash
terragrunt run --all init
```

Use `--backend-bootstrap` only when you intentionally want Terragrunt to be allowed to bootstrap missing backend infrastructure.

An equivalent explicit Terragrunt-only bootstrap sequence is:

```bash
cd vpc
terragrunt backend bootstrap
cd ..
terragrunt run --all init
```

Use one approach or the other. For a brand-new environment, the recommended path is the single command:

```bash
terragrunt run --all --backend-bootstrap init
```

## Component lifecycle

Plan or apply one unit directly:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt plan
terragrunt apply
```

The same pattern works for `vpc`, `ec2`, `k3s`, `cert-manager` and `argocd`.

## Kubeconfig

The node bootstrap writes an operator-facing kubeconfig to `/etc/rancher/k3s/k3s-public.yaml`, with the public API endpoint already substituted.

During `apply`, the K3s unit reads that file off the node through Systems Manager using a `local-exec` provisioner and writes it locally with mode `600`:

```bash
cd infrastructure/live/dev/us-east-1/k3s
terragrunt output kubeconfig_path
```

It defaults to `~/.kube/<cluster>.yaml` and is overridden with the `kubeconfig_path` input. The same content is also a sensitive Terraform output:

```bash
terragrunt output -raw kubeconfig
```

This replaces both the old kubeconfig retrieval shell script and the scoped Parameter Store keys used by earlier revisions.

## Helm releases through Terragrunt

Each platform leaf sources `infrastructure/modules/helm-release`.

The module:

- pins HashiCorp Helm provider `3.2.0`;
- uses K3s API/client outputs for provider authentication;
- installs the official upstream chart directly;
- waits for readiness/jobs;
- uses atomic install/upgrade behavior and cleanup on failure;
- keeps each release in its own Terraform state.

Values are stored under:

```text
kubernetes/helm/traefik/values.yaml
kubernetes/helm/cert-manager/values.yaml
kubernetes/helm/argocd/values.yaml
```

Chart repository/name/version are stored under:

```text
infrastructure/live/_common/traefik.hcl
infrastructure/live/_common/cert-manager.hcl
infrastructure/live/_common/argocd.hcl
```

No local wrapper `Chart.yaml`, `install.sh`, `uninstall.sh`, or `helm dependency update` step is needed.

## Destroy

From the region directory:

```bash
terragrunt run --all destroy
```

The reverse dependency graph removes Argo CD and cert-manager/Traefik before K3s, then removes EC2 and VPC.

## State and secrets

Remote state is S3-backed and encrypted. State still contains sensitive Kubernetes client material because Terraform providers need it. Treat state access like production credentials:

- restrict IAM access to the state bucket;
- never commit local state;
- keep S3 public access blocked;
- retain state locking;
- use separate state paths per environment/region/component;
- rotate K3s credentials if state is exposed.

## Existing release import

If Traefik, cert-manager or Argo CD already exists from the old shell/Helm workflow, import it before the first apply of the corresponding unit:

```bash
cd infrastructure/live/dev/us-east-1/traefik
terragrunt import helm_release.this traefik/traefik

cd ../cert-manager
terragrunt import helm_release.this cert-manager/cert-manager

cd ../argocd
terragrunt import helm_release.this argocd/argocd
```

Review each `terragrunt plan` after import. The new model manages upstream charts directly rather than the removed local wrapper charts.
