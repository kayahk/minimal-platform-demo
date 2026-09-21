output "namespaces" {
  value = keys(local.namespaces)
}

output "applications" {
  value = [for t in local.targets : "${t.project}-${t.service}-${t.environment}"]
}

output "vault_addr" {
  value = "http://127.0.0.1:8200"
}

output "argocd_namespace" {
  value = "argocd"
}
