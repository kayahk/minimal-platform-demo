from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_up_script_can_use_an_existing_minikube_profile():
    script = read("scripts/up.sh")

    assert 'PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"' in script
    assert 'minikube start --profile "$CLUSTER_NAME"' in script
    assert 'kubectl config use-context "$KUBE_CONTEXT"' in script


def test_variables_default_to_platform_demo_context():
    content = read("variables.tf")

    assert 'default     = "platform-demo"' in content


def test_argocd_applicationsets_use_kubectl_after_crds_exist():
    module = read("modules/argocd/main.tf")

    assert 'resource "terraform_data" "workloads"' in module
    assert 'resource "terraform_data" "databases"' in module
    assert 'kubectl --context ${var.kube_context} apply -f -' in module
    assert 'resource "kubernetes_manifest" "workloads"' not in module


def test_database_application_carries_the_service_identity_into_the_claim():
    application_set = read("modules/argocd/applicationset-databases.yaml.tftpl")
    claim = read("charts/database-claim/templates/database.yaml")

    assert 'service: "{{.serviceName}}"' in application_set
    assert 'platform.demo/service: {{ .Values.service | quote }}' in claim
