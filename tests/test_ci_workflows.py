from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_down_script_deletes_the_selected_runtime_cluster():
    script = read("scripts/down.sh")

    assert 'PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"' in script
    assert 'minikube delete --profile "$CLUSTER_NAME"' in script
    assert 'rm -f "${ROOT}/terraform.tfstate"*' in script
    assert 'TF_VAR_kube_context="$KUBE_CONTEXT" "$TF" destroy' in script


def test_up_script_passes_enable_custom_resources_on_second_apply():
    script = read("scripts/up.sh")

    assert 'apply -input=false -auto-approve -var enable_custom_resources=true' in script


def test_up_script_prints_a_runtime_specific_vault_endpoint():
    script = read("scripts/up.sh")

    assert 'minikube ip --profile "$CLUSTER_NAME"' in script
    assert 'VAULT_ADDR="http://$VAULT_HOST:30200"' in script


def test_vault_custom_resources_wait_for_the_operator_crds():
    module = read("modules/vault-secrets-operator/main.tf")

    assert 'count = var.enable_custom_resources ? 1 : 0' in module


def test_database_chart_declares_its_service_value():
    values = read("charts/database-claim/values.yaml")

    assert 'service: ""' in values


def test_validation_workflow_checks_registry_rendering_and_policies():
    workflow = read(".github/workflows/validate.yaml")

    assert 'pull_request:' in workflow
    assert 'python3 scripts/validate-registry.py' in workflow
    assert 'scripts/render-and-check-policies.sh' in workflow
    assert 'kyverno/action-install-cli' in workflow
    assert 'tofu validate' in workflow


def test_policy_renderer_is_offline_and_does_not_require_a_kubernetes_api():
    script = read("scripts/render-and-check-policies.sh")

    assert 'kubectl apply --dry-run=client --validate=false --server-side=false --openapi-patch=false' in script


def test_validation_workflow_has_no_narrow_path_filter_regression():
    workflow = read(".github/workflows/validate.yaml")

    assert 'paths:' not in workflow
