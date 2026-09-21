resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.chart_version
  namespace  = kubernetes_namespace.vault.metadata[0].name
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      global = {
        enabled = true
      }
      server = {
        dev = {
          enabled      = true
          devRootToken = var.root_token
        }
        service = {
          type     = "NodePort"
          nodePort = 30200
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
        }
      }
      injector = {
        enabled = false
      }
      csi = {
        enabled = false
      }
    })
  ]
}

resource "kubernetes_config_map" "bootstrap" {
  metadata {
    name      = "vault-bootstrap"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  data = {
    "bootstrap.sh" = templatefile("${path.module}/bootstrap.sh.tftpl", {
      root_token = var.root_token
      policies   = local.policies
      roles      = local.roles
      targets    = var.targets
    })
  }
}

locals {
  policies = {
    for role in distinct([for t in var.targets : t.vault_policy]) : role => join("\n", flatten([
      for t in var.targets : t.vault_policy == role ? [
        "path \"secrets/data/${t.environment}/${t.project}-${t.service}/*\" { capabilities = [\"read\", \"list\"] }",
        "path \"secrets/metadata/${t.environment}/${t.project}-${t.service}/*\" { capabilities = [\"read\", \"list\"] }",
        "path \"configurations/data/${t.environment}/${t.project}-${t.service}/*\" { capabilities = [\"read\", \"list\"] }",
        "path \"configurations/metadata/${t.environment}/${t.project}-${t.service}/*\" { capabilities = [\"read\", \"list\"] }",
      ] : []
    ]))
  }

  roles = {
    for role in distinct([for t in var.targets : t.vault_role]) : role => {
      policy     = one(distinct([for t in var.targets : t.vault_policy if t.vault_role == role]))
      sa_name    = one(distinct([for t in var.targets : t.service_account if t.vault_role == role]))
      namespaces = distinct([for t in var.targets : t.namespace if t.vault_role == role])
    }
  }
}

resource "kubernetes_service_account" "bootstrap" {
  metadata {
    name      = "vault-bootstrap"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "bootstrap" {
  metadata {
    name = "vault-bootstrap-auth-delegator"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.bootstrap.metadata[0].name
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
}

resource "kubernetes_job" "bootstrap" {
  metadata {
    name      = "vault-bootstrap"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  spec {
    ttl_seconds_after_finished = 120
    template {
      metadata {
        labels = {
          app = "vault-bootstrap"
        }
      }
      spec {
        restart_policy                  = "OnFailure"
        service_account_name            = kubernetes_service_account.bootstrap.metadata[0].name
        automount_service_account_token = true
        container {
          name    = "bootstrap"
          image   = "hashicorp/vault:1.18.4"
          command = ["sh", "/scripts/bootstrap.sh"]
          env {
            name  = "VAULT_ADDR"
            value = "http://vault:8200"
          }
          env {
            name  = "VAULT_TOKEN"
            value = var.root_token
          }
          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }
        }
        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.bootstrap.metadata[0].name
            default_mode = "0755"
          }
        }
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
    update = "5m"
  }

  depends_on = [
    helm_release.vault,
    kubernetes_cluster_role_binding.bootstrap,
  ]
}
