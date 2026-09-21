resource "kubernetes_namespace" "vso" {
  metadata {
    name = "vault-secrets-operator-system"
  }
}

resource "helm_release" "vso" {
  name       = "vault-secrets-operator"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault-secrets-operator"
  version    = var.chart_version
  namespace  = kubernetes_namespace.vso.metadata[0].name
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      defaultVaultConnection = {
        enabled       = true
        address       = "http://vault.vault.svc.cluster.local:8200"
        skipTLSVerify = true
      }
      controller = {
        manager = {
          resources = {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }
      }
    })
  ]
}

resource "kubernetes_service_account" "service" {
  for_each = { for t in var.targets : t.namespace => t }

  metadata {
    name      = each.value.service_account
    namespace = each.value.namespace
  }
}

resource "kubernetes_manifest" "vault_auth" {
  for_each = var.enable_custom_resources ? { for t in var.targets : t.namespace => t } : {}

  manifest = {
    apiVersion = "secrets.hashicorp.com/v1beta1"
    kind       = "VaultAuth"
    metadata = {
      name      = "default"
      namespace = each.value.namespace
    }
    spec = {
      method = "kubernetes"
      mount  = "kubernetes"
      kubernetes = {
        role           = each.value.vault_role
        serviceAccount = each.value.service_account
        audiences      = ["vault"]
      }
      vaultConnectionRef = "${kubernetes_namespace.vso.metadata[0].name}/default"
    }
  }

  depends_on = [
    helm_release.vso,
    kubernetes_service_account.service,
  ]
}
