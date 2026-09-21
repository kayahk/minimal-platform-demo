#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_unix

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
CLUSTER_NAME="platform-demo"
PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"
cd "$ROOT"

APP_FORWARD_PID="${ROOT}/.demo-app-port-forward.pid"
if [[ -f "$APP_FORWARD_PID" ]]; then
  old_pid="$(cat "$APP_FORWARD_PID" 2>/dev/null || true)"
  if [[ -n "${old_pid}" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "stopping demo app port-forward (${old_pid})"
    kill "$old_pid" 2>/dev/null || true
  fi
  rm -f "$APP_FORWARD_PID"
fi
rm -f "${ROOT}/.demo-app-port-forward.log"

if command -v tofu >/dev/null 2>&1; then
  TF=tofu
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

case "$PLATFORM_DEMO_RUNTIME" in
  minikube)
    if command -v minikube >/dev/null 2>&1 && minikube status --profile "$CLUSTER_NAME" >/dev/null 2>&1; then
      echo "deleting minikube profile ${CLUSTER_NAME}"
      minikube delete --profile "$CLUSTER_NAME"
    fi
    rm -f "${TF_DIR}/terraform.tfstate"*
    ;;
  kind)
    if [[ -n "$TF" && -f "${TF_DIR}/terraform.tfstate" ]]; then
      TF_VAR_kube_context="$KUBE_CONTEXT" "$TF" -chdir="$TF_DIR" destroy -input=false -auto-approve || true
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
    ;;
esac

echo "demo cluster removed"
