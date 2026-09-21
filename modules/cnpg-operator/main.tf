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
