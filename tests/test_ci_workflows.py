from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_validation_workflow_checks_registry_rendering_and_policies():
    workflow = read(".github/workflows/validate.yaml")

    assert 'pull_request:' in workflow
    assert 'python3 scripts/validate-registry.py' in workflow
    assert 'scripts/render-and-check-policies.sh' in workflow
    assert 'kyverno/action-install-cli' in workflow
    assert 'tofu validate' in workflow


def test_vault_sync_runs_only_after_registry_changes_reach_main():
    workflow = read(".github/workflows/vault-registry-sync.yaml")

    assert 'push:' in workflow
    assert '- "registry/**/config.json"' in workflow
    assert 'branches: [main]' in workflow
    assert 'git diff --name-status' in workflow
    assert 'tofu apply -input=false -auto-approve -target=module.vault' in workflow
    assert 'minikube start --profile platform-demo' in workflow
    assert 'minikube-linux-amd64' in workflow
