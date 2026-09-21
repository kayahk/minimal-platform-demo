variable "database_targets" {
  type = list(object({
    namespace   = string
    project     = string
    service     = string
    environment = string
  }))
  default     = []
  description = "Workload namespaces that should receive a copy of the CNPG app role credentials."
}

resource "kubernetes_namespace" "cnpg" {
  metadata {
    name = "cnpg-system"
  }
}

resource "helm_release" "cnpg" {
  name       = "cloudnative-pg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = var.chart_version
  namespace  = kubernetes_namespace.cnpg.metadata[0].name
  wait       = true
  timeout    = 600
}

resource "kubernetes_manifest" "cluster" {
  count = var.enable_custom_resources ? 1 : 0

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = "platform-postgres"
      namespace = kubernetes_namespace.cnpg.metadata[0].name
    }
    spec = {
      instances = 1
      storage = {
        size = "1Gi"
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
    }
  }

  depends_on = [helm_release.cnpg]
}

resource "terraform_data" "wait_app_secret" {
  count = var.enable_custom_resources ? 1 : 0

  input = try(kubernetes_manifest.cluster[0].object.metadata.uid, "pending")

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command     = "kubectl -n ${kubernetes_namespace.cnpg.metadata[0].name} wait --for=jsonpath='{.data.password}' secret/platform-postgres-app --timeout=300s"
  }

  depends_on = [kubernetes_manifest.cluster]
}

data "kubernetes_secret_v1" "app" {
  count = var.enable_custom_resources ? 1 : 0

  metadata {
    name      = "platform-postgres-app"
    namespace = kubernetes_namespace.cnpg.metadata[0].name
  }

  depends_on = [terraform_data.wait_app_secret]
}

resource "kubernetes_secret_v1" "workload_postgres" {
  for_each = var.enable_custom_resources ? {
    for t in var.database_targets : t.namespace => t
  } : {}

  metadata {
    name      = "postgres-app"
    namespace = each.value.namespace
    labels = {
      "platform.demo/project"     = each.value.project
      "platform.demo/service"     = each.value.service
      "platform.demo/environment" = each.value.environment
    }
    annotations = {
      "platform.demo/copied-from" = "cnpg-system/platform-postgres-app"
    }
  }

  data = {
    username = data.kubernetes_secret_v1.app[0].data["username"]
    password = data.kubernetes_secret_v1.app[0].data["password"]
  }

  type = "kubernetes.io/basic-auth"
}
