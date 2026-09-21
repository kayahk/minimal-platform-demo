from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_down_script_deletes_the_selected_runtime_cluster():
    script = read("scripts/down.sh")

    assert 'PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"' in script
    assert 'minikube delete --profile "$CLUSTER_NAME"' in script
    assert 'rm -f "${TF_DIR}/terraform.tfstate"*' in script
    assert 'TF_VAR_kube_context="$KUBE_CONTEXT" "$TF" -chdir="$TF_DIR" destroy' in script
    assert ".demo-app-port-forward.pid" in script
    assert 'kill "$old_pid"' in script
    assert 'command -v tofu' in script
    assert 'command -v terraform' not in script
    assert "/lib.sh" in script


def test_up_script_passes_enable_custom_resources_on_second_apply():
    script = read("scripts/up.sh")

    assert 'apply -input=false -auto-approve -var enable_custom_resources=true' in script
    assert '"$TF" -chdir="$TF_DIR" init' in script
    assert '"$TF" -chdir="$TF_DIR" apply' in script
    assert 'need tofu' in script
    assert 'TF=tofu' in script
    assert 'command -v terraform' not in script
    assert "-target=module.namespace_hibernation.helm_release.downscaler" in script
    assert 'export TF_VAR_host_timezone=' in script
    assert "/lib.sh" in script
    assert "b64decode" in script


def test_up_script_prints_runtime_specific_argocd_and_vault_urls():
    script = read("scripts/up.sh")

    assert 'ARGOCD_ADDR="http://${MINIKUBE_IP}:30080"' in script
    assert 'ARGOCD_ADDR="http://127.0.0.1:8081"' in script
    assert "do not port-forward onto 8081" in script
    assert "kubectl -n project-a-int port-forward --address 127.0.0.1 svc/int 9090:80" in script
    assert ".demo-app-port-forward.pid" in script
    assert "http://127.0.0.1:9090" in script
    assert 'VAULT_ADDR="http://${MINIKUBE_IP}:30200"' in script
    assert 'VAULT_ADDR="http://127.0.0.1:8200"' in script
    assert "Kind maps Vault NodePort 30200 to host port 8200" in script
    assert "1. Argo CD UI" in script
    assert "2. push-service" in script
    assert "3. Vault" in script
    assert "NOT the demo app" in script


def test_readme_documents_the_three_demo_endpoints():
    readme = read("README.md")

    assert "## Access the demo" in readme
    assert "http://127.0.0.1:9090" in readme
    assert "http://127.0.0.1:8081" in readme
    assert "http://127.0.0.1:8200" in readme
    assert "30080" in readme
    assert "project-a-push-service-int" in readme
    assert "hello from Vault (int)" in readme
    assert "hibernate: true" in readme
    assert "GoKubeDownscaler" in readme
    assert "macOS or Linux" in readme
    assert "host timezone" in readme
    assert "open http://" not in readme
    assert "Europe/Berlin" not in readme
    assert "OpenTofu or Terraform" not in readme
    assert "## Acknowledgements" in readme
    assert "not affiliated with" in readme


def test_vso_helm_release_owns_the_default_vault_connection():
    module = read("terraform/modules/vault-secrets-operator/main.tf")

    assert 'defaultVaultConnection = {' in module
    assert 'enabled       = true' in module
    assert 'resource "kubernetes_manifest" "vault_connection"' not in module


def test_vault_custom_resources_wait_for_the_operator_crds():
    module = read("terraform/modules/vault-secrets-operator/main.tf")

    assert 'for_each = var.enable_custom_resources ?' in module


def test_database_chart_declares_its_service_value():
    values = read("charts/database-claim/values.yaml")

    assert 'service: ""' in values


def test_opentofu_root_module_lives_under_terraform():
    assert (ROOT / "terraform" / "main.tf").is_file()
    assert (ROOT / "terraform" / "modules" / "argocd" / "main.tf").is_file()
    assert not (ROOT / "main.tf").exists()
    assert not (ROOT / "modules").exists()


def test_validation_workflow_checks_registry_rendering_and_policies():
    workflow = read(".github/workflows/validate.yaml")

    assert 'pull_request:' in workflow
    assert 'python3 scripts/validate-registry.py' in workflow
    assert 'scripts/render-and-check-policies.sh' in workflow
    assert 'kyverno/action-install-cli' in workflow
    assert 'tofu fmt -check -recursive terraform' in workflow
    assert 'tofu -chdir=terraform init -backend=false -input=false' in workflow
    assert 'tofu -chdir=terraform validate' in workflow


def test_policy_renderer_is_offline_and_does_not_require_a_kubernetes_api():
    script = read("scripts/render-and-check-policies.sh")

    assert 'need kubectl' not in script
    assert 'kubectl apply' not in script
    assert 'kyverno apply policies/kyverno --resource' in script
    assert 'need tofu' in script
    assert 'command -v terraform' not in script


def test_validation_workflow_has_no_narrow_path_filter_regression():
    workflow = read(".github/workflows/validate.yaml")

    assert 'paths:' not in workflow
