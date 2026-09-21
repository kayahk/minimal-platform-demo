from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_up_script_can_use_an_existing_minikube_profile():
    script = read("scripts/up.sh")

    assert 'PLATFORM_DEMO_RUNTIME="${PLATFORM_DEMO_RUNTIME:-minikube}"' in script
    assert 'minikube start --profile "$CLUSTER_NAME"' in script
    assert 'kubectl config use-context "$KUBE_CONTEXT"' in script
    assert "Darwin | Linux" in read("scripts/lib.sh")
    assert "host_timezone()" in read("scripts/lib.sh")


def test_host_timezone_helper_returns_iana_or_utc():
    import subprocess

    zone = subprocess.check_output(
        ["bash", "-c", ". scripts/lib.sh && host_timezone"],
        cwd=ROOT,
        text=True,
    ).strip()

    assert zone == "UTC" or "/" in zone
    assert " " not in zone


def test_variables_default_to_platform_demo_context():
    content = read("terraform/variables.tf")

    assert 'default     = "platform-demo"' in content
    assert 'variable "host_timezone"' in content


def test_argocd_applicationsets_use_kubectl_after_crds_exist():
    module = read("terraform/modules/argocd/main.tf")

    assert 'resource "terraform_data" "workloads"' in module
    assert 'resource "terraform_data" "databases"' in module
    assert 'kubectl --context ${var.kube_context} apply -f -' in module
    assert 'interpreter = ["/usr/bin/env", "bash", "-c"]' in module
    assert 'resource "kubernetes_manifest" "workloads"' not in module


def test_database_application_carries_the_service_identity_into_the_claim():
    application_set = read("terraform/modules/argocd/applicationset-databases.yaml.tftpl")
    claim = read("charts/database-claim/templates/database.yaml")

    assert 'service: "{{.serviceName}}"' in application_set
    assert 'platform.demo/service: {{ .Values.service | quote }}' in claim


def test_argocd_is_exposed_on_nodeport_30080():
    module = read("terraform/modules/argocd/main.tf")
    kind = read("kind.yaml")

    assert "nodePortHttp = 30080" in module
    assert "containerPort: 30080" in kind
    assert "hostPort: 8081" in kind


def test_workload_chart_declares_vault_static_secrets():
    chart = read("charts/common-service/templates/vaultstaticsecret.yaml")
    deployment = read("charts/common-service/templates/deployment.yaml")
    bootstrap = read("terraform/modules/vault/bootstrap.sh.tftpl")

    assert "kind: VaultStaticSecret" in chart
    assert "excludeRaw: true" in chart
    assert "secretName: {{ $.Release.Name }}-{{ . }}-demo" in deployment
    assert "hello from Vault" in bootstrap
    assert "audience=vault" in bootstrap


def test_vault_policy_template_is_generic_and_rendered_by_opentofu():
    template = read("policies/vault/service-access.hcl")
    module = read("terraform/modules/vault/main.tf")

    assert "{{env}}" in template
    assert "{{project}}" in template
    assert "{{service}}" in template
    assert "project-a-push-service" not in template
    assert 'file("${path.root}/../policies/vault/service-access.hcl")' in module
    assert not (ROOT / "policies/vault/project-a-push-service-access.hcl").exists()


def test_applicationset_passes_vault_identity_into_the_workload_chart():
    application_set = read("terraform/modules/argocd/applicationset-workloads.yaml.tftpl")

    assert "vault:" in application_set
    assert "enabled: {{.vaultOperator}}" in application_set
    assert "pathPrefixes: [{{ range $i, $p := .vaultPathPrefixes }}" in application_set
    assert "repoURL: ${repo_url}" in application_set
    assert "targetRevision: ${repo_revision}" in application_set
    assert "{{.spec.source.repoURL}}" not in application_set


def test_argocd_serves_a_local_git_snapshot_to_applications():
    module = read("terraform/modules/argocd/git-server.tf")
    argocd = read("terraform/modules/argocd/main.tf")

    assert "file:///git/demo.git" in module
    assert "resource \"kubernetes_config_map\" \"demo_git_src\"" in module
    assert "local.demo_git_url" in argocd
    assert "initContainers" in argocd


def test_hibernate_installs_gokube_downscaler_and_annotates_namespaces():
    module = read("terraform/modules/namespace-hibernation/main.tf")

    assert 'chart      = "go-kube-downscaler"' in module
    assert '"downscaler/uptime" = var.uptime' in module
    assert '"argocd"' in module
    assert '"cnpg-system"' in module
    assert "kube-downscaler" in module
    root = read("terraform/main.tf")
    assert 'uptime     = "Mon-Fri 08:00-18:00 ${var.host_timezone}"' in root


def test_hibernated_applications_do_not_fight_the_downscaler():
    application_set = read("terraform/modules/argocd/applicationset-workloads.yaml.tftpl")

    assert "{{- if .hibernate }}" in application_set
    assert "templatePatch:" in application_set
    assert "RespectIgnoreDifferences=true" in application_set
    assert "/spec/replicas" in application_set
