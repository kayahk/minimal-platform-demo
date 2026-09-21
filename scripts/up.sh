#!/usr/bin/env bash
# Bring up a local cluster and apply the platform demo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER_NAME="platform-demo"
PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"
KIND_VERSION="v0.27.0"
cd "$ROOT"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need docker
need kubectl
need helm
if command -v tofu >/dev/null 2>&1; then
  TF=tofu
elif command -v terraform >/dev/null 2>&1; then
  TF=terraform
else
  echo "missing dependency: tofu or terraform" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker is not running" >&2
  exit 1
fi

case "$PLATFORM_DEMO_RUNTIME" in
  minikube)
    need minikube
    if ! minikube status --profile "$CLUSTER_NAME" >/dev/null 2>&1; then
      echo "creating minikube profile ${CLUSTER_NAME}"
      minikube start --profile "$CLUSTER_NAME" --driver=docker --cpus=4 --memory=6000
    else
      echo "minikube profile ${CLUSTER_NAME} already exists"
    fi
    KUBE_CONTEXT="$CLUSTER_NAME"
    ;;
  kind)
    install_kind() {
      local arch os bin
      os="$(uname -s | tr '[:upper:]' '[:lower:]')"
      case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
      esac
      bin="${ROOT}/.bin/kind"
      mkdir -p "${ROOT}/.bin"
      if [[ ! -x "$bin" ]]; then
        echo "downloading kind ${KIND_VERSION}"
        curl -fsSL -o "$bin" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${os}-${arch}"
        chmod +x "$bin"
      fi
      echo "$bin"
    }

    if command -v kind >/dev/null 2>&1; then
      KIND=kind
    else
      KIND="$(install_kind)"
    fi

    if ! "${KIND}" get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
      echo "creating kind cluster ${CLUSTER_NAME}"
      "${KIND}" create cluster --config "${ROOT}/kind.yaml"
    else
      echo "kind cluster ${CLUSTER_NAME} already exists"
    fi
    KUBE_CONTEXT="kind-${CLUSTER_NAME}"
    ;;
  *)
    echo "unsupported PLATFORM_DEMO_RUNTIME: $PLATFORM_DEMO_RUNTIME (use minikube or kind)" >&2
    exit 1
    ;;
esac

kubectl config use-context "$KUBE_CONTEXT" >/dev/null
export TF_VAR_kube_context="$KUBE_CONTEXT"

if [[ "$PLATFORM_DEMO_RUNTIME" == "minikube" ]]; then
  VAULT_ADDR="http://$(minikube ip --profile "$CLUSTER_NAME"):30200"
  VAULT_HINT="run \"minikube service -n vault vault --url --profile ${CLUSTER_NAME}\" if direct IP is unreachable"
else
  VAULT_ADDR="http://127.0.0.1:8200"
  VAULT_HINT="Kind maps the Vault NodePort to host port 8200"
fi

echo "initialising terraform"
"$TF" init -input=false

echo "installing operators"
"$TF" apply -input=false -auto-approve \
  -target=module.kyverno.helm_release.kyverno \
  -target=module.cnpg_operator.helm_release.cnpg \
  -target=module.vault.helm_release.vault \
  -target=module.argocd.helm_release.argocd \
  -target=module.vault_secrets_operator.helm_release.vso

echo "waiting for CRDs"
kubectl wait --for=condition=Established --timeout=180s \
  crd/applicationsets.argoproj.io \
  crd/clusters.postgresql.cnpg.io \
  crd/clusterpolicies.kyverno.io \
  crd/vaultauths.secrets.hashicorp.com \
  crd/vaultconnections.secrets.hashicorp.com

echo "applying Kyverno policies"
kubectl apply -f "${ROOT}/policies/kyverno"

echo "applying remaining platform consumers"
"$TF" apply -input=false -auto-approve -var enable_custom_resources=true

echo "waiting for Argo CD applications"
if ! kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/project-a-push-service-int \
  --timeout=180s 2>/dev/null; then
  echo "Argo CD is still syncing. Check: kubectl -n argocd get applications"
fi

PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode)"

cat <<EOF

Demo is up.

  cluster:     ${KUBE_CONTEXT} (${PLATFORM_DEMO_RUNTIME})
  namespaces:  project-a-dev, project-a-int
  applications: project-a-push-service-dev, project-a-push-service-int
  vault:       ${VAULT_ADDR} (token: root)
  vault url:   ${VAULT_HINT}
  argocd:      kubectl -n argocd port-forward svc/argo-cd-argocd-server 8081:80
               user admin  password ${PASSWORD}

The registry file is registry/dev/project-a/push-service/config.json.
Change it, commit, push, and Argo CD will reconcile.

Tear down with: ./scripts/down.sh
EOF
