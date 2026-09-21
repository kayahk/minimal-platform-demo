#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER_NAME="platform-demo"
PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"
cd "$ROOT"

if command -v tofu >/dev/null 2>&1; then
  TF=tofu
elif command -v terraform >/dev/null 2>&1; then
  TF=terraform
else
  TF=""
fi

case "$PLATFORM_DEMO_RUNTIME" in
  minikube)
    KUBE_CONTEXT="$CLUSTER_NAME"
    ;;
  kind)
    KUBE_CONTEXT="kind-${CLUSTER_NAME}"
    ;;
  *)
    echo "unsupported PLATFORM_DEMO_RUNTIME: $PLATFORM_DEMO_RUNTIME (use minikube or kind)" >&2
    exit 1
    ;;
esac

if [[ -n "$TF" && -f "${ROOT}/terraform.tfstate" ]]; then
  TF_VAR_kube_context="$KUBE_CONTEXT" "$TF" destroy -input=false -auto-approve || true
fi

case "$PLATFORM_DEMO_RUNTIME" in
  minikube)
    if command -v minikube >/dev/null 2>&1 && minikube status --profile "$CLUSTER_NAME" >/dev/null 2>&1; then
      echo "deleting minikube profile ${CLUSTER_NAME}"
      minikube delete --profile "$CLUSTER_NAME"
    fi
    ;;
  kind)
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
    ;;
esac

echo "demo cluster removed"
