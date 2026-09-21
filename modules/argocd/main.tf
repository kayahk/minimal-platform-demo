resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        extraArgs = ["--insecure"]
      }
      notifications = {
        enabled = false
      }
    })
  ]
}

resource "kubernetes_manifest" "workloads" {
  manifest = yamldecode(templatefile("${path.module}/applicationset-workloads.yaml.tftpl", {
    repo_url      = var.repo_url
    repo_revision = var.repo_revision
  }))
  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "databases" {
  manifest = yamldecode(templatefile("${path.module}/applicationset-databases.yaml.tftpl", {
    repo_url      = var.repo_url
    repo_revision = var.repo_revision
  }))
  depends_on = [helm_release.argocd]
}
