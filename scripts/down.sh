#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER_NAME="platform-demo"
cd "$ROOT"

if command -v tofu >/dev/null 2>&1; then
  TF=tofu
elif command -v terraform >/dev/null 2>&1; then
  TF=terraform
else
  TF=""
fi

if [[ -n "$TF" && -f "${ROOT}/terraform.tfstate" ]]; then
  "$TF" destroy -input=false -auto-approve || true
fi

if command -v kind >/dev/null 2>&1; then
  KIND=kind
elif [[ -x "${ROOT}/.bin/kind" ]]; then
  KIND="${ROOT}/.bin/kind"
else
  KIND=""
fi

if [[ -n "$KIND" ]] && "$KIND" get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "deleting kind cluster ${CLUSTER_NAME}"
  "$KIND" delete cluster --name "$CLUSTER_NAME"
fi

echo "demo cluster removed"
