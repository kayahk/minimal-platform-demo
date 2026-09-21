resource "kubernetes_namespace" "kyverno" {
  metadata {
    name = "kyverno"
  }
}

resource "helm_release" "kyverno" {
  name       = "kyverno"
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno"
  version    = var.chart_version
  namespace  = kubernetes_namespace.kyverno.metadata[0].name
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      admissionController  = { replicas = 1 }
      backgroundController = { replicas = 1 }
      cleanupController    = { replicas = 1 }
      reportsController    = { replicas = 1 }
    })
  ]
}
