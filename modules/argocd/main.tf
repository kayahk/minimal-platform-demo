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

resource "terraform_data" "workloads" {
  triggers_replace = [sha256(templatefile("${path.module}/applicationset-workloads.yaml.tftpl", {
    repo_url      = var.repo_url
    repo_revision = var.repo_revision
  }))]

  provisioner "local-exec" {
    command = <<-EOT
      cat <<'MANIFEST' | kubectl --context ${var.kube_context} apply -f -
      ${templatefile("${path.module}/applicationset-workloads.yaml.tftpl", {
    repo_url      = var.repo_url
    repo_revision = var.repo_revision
})}
      MANIFEST
    EOT
}

depends_on = [helm_release.argocd]
}

resource "terraform_data" "databases" {
  triggers_replace = [sha256(templatefile("${path.module}/applicationset-databases.yaml.tftpl", {
    repo_url      = var.repo_url
    repo_revision = var.repo_revision
  }))]

  provisioner "local-exec" {
    command = <<-EOT
      cat <<'MANIFEST' | kubectl --context ${var.kube_context} apply -f -
      ${templatefile("${path.module}/applicationset-databases.yaml.tftpl", {
    repo_url      = var.repo_url
    repo_revision = var.repo_revision
})}
      MANIFEST
    EOT
}

depends_on = [helm_release.argocd]
}
