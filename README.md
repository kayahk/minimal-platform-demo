# minimal-platform-demo

Companion to the blog article about building an internal developer platform backwards from one reviewed `config.json`. 

[https://looks.ratherbumpy.com/2026/09/a-powerful-platform-can-start-real-tiny.html](https://looks.ratherbumpy.com/2026/09/a-powerful-platform-can-start-real-tiny.html)

Clone this repository and run one command to stand up the model on a local Kubernetes cluster.

![A JSON file powers the platform](img/json-file-powers-platform.jpg)

## Demo Scope vs. Production Reality

This repository is a self-contained, educational model designed to illustrate the control plane mechanics described in the blog post. In a real-world enterprise IDP, several structural differences and architectural separations apply:

- **Repository Separation & Cross-Repo GitOps**:
In production, the service registry lives in its own dedicated repository, owned by developers and subject to strict PR policy checks. Merges to that registry trigger automated downstream workflows in a separate platform GitOps/infrastructure repository to deliver platform updates, Vault roles, and Argo CD configurations. In this demo, the registry, charts, OpenTofu modules, and CI workflows are consolidated into a single repo for simplicity and local execution.
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
img/                README headliner diagram
```

