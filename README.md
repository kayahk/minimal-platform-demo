# minimal-platform-demo

Companion to the blog article about building an internal developer platform backwards from one reviewed `config.json`. Clone this repository and run one command to stand up a Kind cluster that follows that model.

This is a local demonstration, not a production platform. Vault runs in dev mode with a well-known root token.

## One command

```bash
git clone https://github.com/kayahk/minimal-platform-demo.git
cd minimal-platform-demo
./scripts/up.sh
```

Requires Docker, kubectl, Helm, and OpenTofu or Terraform. If `kind` is missing, the script downloads it into `.bin/`.

Tear down with `./scripts/down.sh`.

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
registry/     service contract (config.json) and JSON Schema
modules/      OpenTofu modules for cluster operators
  argo-cd, vault, vault-secrets-operator, cnpg-operator, kyverno,
  namespace-hibernation
policies/     Vault policy source of truth and Kyverno ClusterPolicies
charts/       shared workload chart and CNPG database claim chart
apps/         values for push-service
scripts/      up.sh, down.sh, registry validation
```

## How a field becomes a resource

| Registry field | Consumer |
|---|---|
| `spec.source` / `spec.valuesSource` / `spec.environments[]` | Argo CD ApplicationSet |
| `spec.environments[].hibernate` | namespace annotation `downscaler/uptime` |
| `vaultOperator` / `vaultPathPrefixes` | Vault policy, K8s auth role, VaultAuth |
| `spec.database` | companion ApplicationSet + CNPG Database |
| labels on namespaces and Applications | Kyverno audit policies |

The ApplicationSet uses a Git generator on `registry/dev/*/*/config.json` and a list generator that expands `spec.environments[]`. That is the same matrix pattern as the article.

## After it is up

```bash
kubectl -n argocd get applications
kubectl -n project-a-int get pods,sa
kubectl -n cnpg-system get cluster,database
kubectl get ns project-a-dev -o yaml | grep downscaler
```

Vault (NodePort on localhost:8200):

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
vault kv get secrets/int/project-a-push-service/demo
```

## Forks

ApplicationSets clone this GitHub repository. If you fork it, apply with:

```bash
tofu apply -var repo_url=https://github.com/<you>/minimal-platform-demo.git
```

or set `TF_VAR_repo_url` before `./scripts/up.sh`.
