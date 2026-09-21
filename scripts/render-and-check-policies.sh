#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_unix

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need helm
need kyverno

need tofu
TF=tofu

render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

render_workload() {
  local environment=$1
  helm template "$environment" charts/common-service \
    -f apps/push-service/values.yaml \
    -f "apps/push-service/values/${environment}.yaml" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=project-a-push-service-sa \
    --set-string "labels.platform\.demo/project=project-a" \
    --set-string "labels.platform\.demo/service=push-service" \
    --set-string "labels.platform\.demo/environment=${environment}" \
    --set vault.enabled=true \
    --set vault.environment="${environment}" \
    --set vault.project=project-a \
    --set vault.service=push-service \
    --set 'vault.pathPrefixes={secrets,configurations}' \
    >"$render_dir/workload-${environment}.yaml"
}

render_database() {
  local environment=$1
  helm template "project-a-push-service-db-${environment}" charts/database-claim \
    --set cluster.name=platform-postgres \
    --set cluster.namespace=cnpg-system \
    --set project=project-a \
    --set service=push-service \
    --set environment="$environment" \
    --set namespace="project-a-${environment}" \
    --set database.name="${environment}-app" \
    --set database.owner=postgres \
    >"$render_dir/database-${environment}.yaml"
}

for environment in dev int; do
  render_workload "$environment"
  render_database "$environment"
done

for manifest in "$render_dir"/*.yaml; do
  kyverno apply policies/kyverno --resource "$manifest"
done

"$TF" -chdir="${ROOT}/terraform" init -backend=false -input=false
"$TF" -chdir="${ROOT}/terraform" validate
