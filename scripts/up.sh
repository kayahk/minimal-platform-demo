#!/usr/bin/env bash
# Bring up a local cluster and apply the platform demo.
set -euo pipefail

# shellcheck source=lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_unix

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
CLUSTER_NAME="platform-demo"
PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"
KIND_VERSION="v0.27.0"
cd "$ROOT"

HOST_TIMEZONE="$(host_timezone)"
export TF_VAR_host_timezone="$HOST_TIMEZONE"
echo "host timezone: ${HOST_TIMEZONE}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need docker
need kubectl
need helm
need tofu
TF=tofu

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
        need curl
        echo "downloading kind ${KIND_VERSION}"
        curl -fsSL -o "$bin" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${os}-${arch}"
        chmod +x "$bin"
        xattr -d com.apple.quarantine "$bin" 2>/dev/null || true
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
  MINIKUBE_IP="$(minikube ip --profile "$CLUSTER_NAME")"
  VAULT_ADDR="http://${MINIKUBE_IP}:30200"
  ARGOCD_ADDR="http://${MINIKUBE_IP}:30080"
  VAULT_HINT="Vault NodePort is 30200 on the Minikube node. If that IP is unreachable: minikube service -n vault vault --url --profile ${CLUSTER_NAME}"
  ARGOCD_HINT="Argo CD NodePort is 30080 on the Minikube node. Open ${ARGOCD_ADDR} — do not port-forward, and do not use port 8081."
else
  VAULT_ADDR="http://127.0.0.1:8200"
  ARGOCD_ADDR="http://127.0.0.1:8081"
  VAULT_HINT="Kind maps Vault NodePort 30200 to host port 8200"
  ARGOCD_HINT="Kind maps Argo CD NodePort 30080 to host port 8081. Open ${ARGOCD_ADDR} — do not port-forward onto 8081 (Kind already binds it)."
fi

echo "initialising OpenTofu"
"$TF" -chdir="$TF_DIR" init -input=false

echo "installing operators"
"$TF" -chdir="$TF_DIR" apply -input=false -auto-approve \
  -target=module.kyverno.helm_release.kyverno \
  -target=module.cnpg_operator.helm_release.cnpg \
  -target=module.vault.helm_release.vault \
  -target=module.argocd.helm_release.argocd \
  -target=module.vault_secrets_operator.helm_release.vso \
  -target=module.namespace_hibernation.helm_release.downscaler

echo "waiting for CRDs"
kubectl wait --for=condition=Established --timeout=180s \
  crd/applicationsets.argoproj.io \
  crd/clusters.postgresql.cnpg.io \
  crd/clusterpolicies.kyverno.io \
  crd/vaultauths.secrets.hashicorp.com \
  crd/vaultconnections.secrets.hashicorp.com \
  crd/vaultstaticsecrets.secrets.hashicorp.com

echo "applying Kyverno policies"
kubectl apply -f "${ROOT}/policies/kyverno"

echo "applying remaining platform consumers"
"$TF" -chdir="$TF_DIR" apply -input=false -auto-approve -var enable_custom_resources=true

echo "waiting for Argo CD applications"
if ! kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/project-a-push-service-int \
  --timeout=180s 2>/dev/null; then
  echo "Argo CD is still syncing. Check: kubectl -n argocd get applications"
fi

APP_FORWARD_PID="${ROOT}/.demo-app-port-forward.pid"
APP_FORWARD_LOG="${ROOT}/.demo-app-port-forward.log"
APP_ADDR="http://127.0.0.1:9090"

stop_app_forward() {
  if [[ -f "$APP_FORWARD_PID" ]]; then
    local old_pid
    old_pid="$(cat "$APP_FORWARD_PID" 2>/dev/null || true)"
    if [[ -n "${old_pid}" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      wait "$old_pid" 2>/dev/null || true
    fi
    rm -f "$APP_FORWARD_PID"
  fi
}

echo "waiting for the int push-service"
if kubectl -n project-a-int wait --for=condition=available deploy/int --timeout=180s; then
  stop_app_forward
  echo "forwarding demo app to ${APP_ADDR}"
  kubectl -n project-a-int port-forward --address 127.0.0.1 svc/int 9090:80 \
    >"$APP_FORWARD_LOG" 2>&1 &
  echo $! >"$APP_FORWARD_PID"
  for _ in {1..20}; do
    if grep -q "Forwarding from" "$APP_FORWARD_LOG" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done
else
  echo "demo app is not ready yet; skip port-forward"
  APP_ADDR="not forwarded (kubectl -n project-a-int port-forward svc/int 9090:80)"
fi

PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | b64decode)"

cat <<EOF

Demo is up.

  cluster:   ${KUBE_CONTEXT} (${PLATFORM_DEMO_RUNTIME})
  registry:  registry/dev/project-a/push-service/config.json
  timezone:  ${HOST_TIMEZONE}

There are three separate URLs. Argo CD is the GitOps console. The
push-service page is the hello-world app. Vault is the secret store.

------------------------------------------------------------------------------
1. Argo CD UI  — log in here (NOT the demo app, NOT port 9090)
   url:      ${ARGOCD_ADDR}
   user:     admin
   password: ${PASSWORD}
   ${ARGOCD_HINT}

   Open application project-a-push-service-int.
   Synced + Healthy means the platform turned the registry file into
   a workload. The application tree should include VaultStaticSecret.
------------------------------------------------------------------------------
2. push-service  — hello-world app that proves Vault secrets were pulled
   url:      ${APP_ADDR}
   json:     curl -s ${APP_ADDR}/api/secrets
   how:      up.sh already port-forwards svc/int in namespace project-a-int
             to localhost:9090. Do not confuse this with Argo CD.

   expect:   message=hello from Vault (int)
             from secrets/int/project-a-push-service/demo (not in Git)

   kubectl -n project-a-int get vaultauth,vaultstaticsecret,secret
------------------------------------------------------------------------------
3. Vault  — optional, inspect the seeded KV (token: root)
   url:      ${VAULT_ADDR}
   ${VAULT_HINT}

   paths:    secrets/int/project-a-push-service/demo
             configurations/int/project-a-push-service/demo
------------------------------------------------------------------------------

Argo CD clones a local snapshot of charts/, apps/, and registry/ — not
GitHub main. After editing those trees, re-run ./scripts/up.sh.

Tear down with ./scripts/down.sh (this also stops the :9090 forward).

Hibernated namespaces such as project-a-dev stay up Mon-Fri 08:00-18:00 ${HOST_TIMEZONE}.
EOF
