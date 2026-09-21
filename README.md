# minimal-platform-demo

Companion to the blog article about building an internal developer platform backwards from one reviewed `config.json`. Clone this repository and run one command to stand up the model on a local Kubernetes cluster.

## Demo Scope vs. Production Reality

This repository is a self-contained, educational model designed to illustrate the control plane mechanics described in the blog post. In a real-world enterprise IDP, several structural differences and architectural separations apply:

- **Repository Separation & Cross-Repo GitOps**:
  In production, the service registry lives in its own dedicated repository (e.g. `platform-registry`), owned by developers and subject to strict PR policy checks. Merges to that registry trigger automated downstream workflows in a separate platform GitOps/infrastructure repository (e.g. `sgc-platform-services`) to deliver platform updates, Vault roles, and Argo CD configurations. In this demo, the registry, charts, OpenTofu modules, and CI workflows are consolidated into a single repo for simplicity and local execution.
- **Cluster Inventory & Placement**:
  The blog article discusses multi-cluster placement and environments mapped across diverse cloud providers (`clouds`) backed by a cluster inventory catalog. In this demo, there is no cluster inventory: a single local Minikube (or Kind) cluster hosts all namespaces and workloads, and the `clouds` field serves as documented placement intent rather than multi-target routing.
- **Foundation Infrastructure Pre-exists**:
  The demo focuses entirely on the developer-facing platform layer: operators, CRDs, namespace governance, Vault integration, and Argo CD ApplicationSets. In production, foundational infrastructure—such as production-grade managed Kubernetes clusters (AKS/EKS), virtual networks, peering, subnets, DNS forwarding, and cloud identity federations (Workload Identity / UAMI)—is assumed to pre-exist, managed by separate foundational GitOps and IaC lifecycles outside the scope of the developer registry.
- **Security & Ephemeral Setup**:
  Vault runs in dev mode using a hardcoded root token and in-memory storage. Passwords and secrets are generated locally or checked in for demonstration purposes.

---

## One command

```bash
git clone https://github.com/kayahk/minimal-platform-demo.git
cd minimal-platform-demo
./scripts/up.sh
```

Requires Docker, kubectl, Helm, OpenTofu or Terraform, and Minikube. `up.sh` creates or reuses the `platform-demo` Minikube profile. The profile needs 4 CPUs and 6 GiB of Docker Desktop memory.

To use Kind instead, set `PLATFORM_DEMO_RUNTIME=kind`; if `kind` is missing, the script downloads it into `.bin/`.

Tear down with `./scripts/down.sh` (this removes the cluster for the active `PLATFORM_DEMO_RUNTIME`, including the Minikube profile).

## What you get

The registry file is the user-facing API:

```text
registry/dev/project-a/push-service/config.json
```

From `projectName: project-a`, `serviceName: push-service`, and environment `int`, the platform derives:

```text
namespace:       project-a-int
Application:     project-a-push-service-int
Helm release:    int
service account: project-a-push-service-sa
Vault role:      project-a-push-service
Vault policy:    project-a-push-service-access
database name:   int-app
```

The same file also produces `project-a-dev` for the `dev` stage. The folder `dev/` is the onboarding tree, not the environment name.

## Layout

```text
.github/workflows/  CI validation workflow
registry/           service contract (config.json) and JSON Schema
modules/            OpenTofu modules for cluster operators
  argo-cd, vault, vault-secrets-operator, cnpg-operator, kyverno,
  namespace-hibernation
policies/           Vault policy source of truth and Kyverno ClusterPolicies
charts/             shared workload chart and CNPG database claim chart
apps/               values for push-service
scripts/            up.sh, down.sh, registry validation, policy check runner
tests/              pytest contract and CI workflow assertions
```

## How a field becomes a resource

| Registry field | Consumer |
|---|---|
| `spec.source` / `spec.valuesSource` / `spec.environments[]` | Argo CD ApplicationSet |
| `spec.environments[].hibernate` | namespace annotation `downscaler/uptime` |
| `spec.environments[].clouds` | placement intent; the demo records the field but runs one local cluster |
| `vaultOperator` / `vaultPathPrefixes` | Vault policy, Kubernetes auth role, VaultAuth |
| `spec.database` | companion ApplicationSet + CNPG Database |
| labels on namespaces and Applications | Kyverno policy checks |

The ApplicationSet uses a Git generator on `registry/dev/*/*/config.json` and a list generator that expands `spec.environments[]`. That is the same matrix pattern as the article. The demo creates separate workload and database Applications, so a service without `spec.database` does not receive a database claim.

## CI validation

Pull requests and relevant pushes to `main` run `.github/workflows/validate.yaml`. The workflow checks the complete contract before changes are merged:

- validates every registry entry against `registry/schema/config.schema.json`;
- runs the Python regression tests;
- checks OpenTofu formatting and runs `tofu validate` without a backend;
- renders the dev and int workload and database Helm charts;
- validates the rendered Kubernetes manifests without requiring a Kubernetes API server;
- applies the Kyverno policies to the rendered resources.

The local equivalent is:

```bash
python3 scripts/validate-registry.py
python3 -m pytest -q
tofu fmt -check -recursive
tofu init -backend=false -input=false
tofu validate
scripts/render-and-check-policies.sh
```

The renderer is intentionally offline: Helm produces the manifests and the Kyverno CLI evaluates the policies without requiring Kubernetes credentials or a live API server.

## Vault updates

Whenever a service is added, modified, or removed in `registry/`, re-apply the Vault module:

```bash
tofu apply -target=module.vault
```

In a team or production setup, this step is typically automated by a CI/CD pipeline triggered on merge to `main` (for example, targeting an external shared Vault instance). In this local demo, running `tofu apply -target=module.vault` directly updates the local Vault container with the latest roles and policies.

## After it is up

```bash
kubectl -n argocd get applications
kubectl -n project-a-int get pods,sa
kubectl -n cnpg-system get cluster,database
kubectl get ns project-a-dev -o yaml | grep downscaler
```

Vault (default Minikube runtime):

```bash
export VAULT_ADDR="http://$(minikube ip --profile platform-demo):30200"
export VAULT_TOKEN=root
vault kv get secrets/int/project-a-push-service/demo
```

If the Minikube node IP is not directly reachable, use `minikube service -n vault vault --url --profile platform-demo` for the address instead. With `PLATFORM_DEMO_RUNTIME=kind`, Kind maps the Vault NodePort to `http://127.0.0.1:8200`.

## Forks

ApplicationSets clone this GitHub repository. If you fork it, apply with:

```bash
tofu apply -var repo_url=https://github.com/<you>/minimal-platform-demo.git
```

or set `TF_VAR_repo_url` before `./scripts/up.sh`.
