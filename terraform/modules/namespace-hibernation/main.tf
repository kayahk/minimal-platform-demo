resource "kubernetes_namespace" "downscaler" {
  metadata {
    name = "kube-downscaler"
  }
}

resource "helm_release" "downscaler" {
  name       = "go-kube-downscaler"
  repository = "https://caas-team.github.io/helm-charts/"
  chart      = "go-kube-downscaler"
  version    = var.chart_version
  namespace  = kubernetes_namespace.downscaler.metadata[0].name
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      replicaCount      = 1
      includedResources = ["deployments"]
      extraArguments    = ["--interval=30"]
      excludedNamespaces = [
        "kube-downscaler",
        "kube-system",
        "kube-public",
        "kube-node-lease",
        "default",
        "argocd",
        "vault",
        "kyverno",
        "cnpg-system",
        "vault-secrets-operator-system",
        "local-path-storage",
      ]
      resources = {
        requests = {
          cpu    = "25m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }
    })
  ]
}

resource "kubernetes_namespace" "stage" {
  for_each = var.namespaces

  metadata {
    name = each.key
    labels = {
      "platform.demo/project"     = each.value.project
      "platform.demo/service"     = each.value.service
      "platform.demo/environment" = each.value.environment
      "platform.demo/hibernate"   = each.value.hibernate ? "true" : "false"
    }
    annotations = each.value.hibernate ? {
      "downscaler/uptime" = var.uptime
    } : {}
  }
}
