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
        repositories = {
          "local-demo" = {
            url  = local.demo_git_url
            name = "local-demo"
            type = "git"
          }
        }
      }
      server = {
        extraArgs = ["--insecure"]
        service = {
          type         = "NodePort"
          nodePortHttp = 30080
        }
      }
      notifications = {
        enabled = false
      }
      repoServer = {
        podAnnotations = {
          "checksum/demo-src" = data.archive_file.demo_src.output_sha
        }
        env = [
          { name = "GIT_CONFIG_COUNT", value = "1" },
          { name = "GIT_CONFIG_KEY_0", value = "safe.directory" },
          { name = "GIT_CONFIG_VALUE_0", value = "*" },
        ]
        initContainers = [
          {
            name  = "unzip-demo-src"
            image = "python:3.12.10-alpine3.21"
            command = [
              "python",
              "-c",
              "import zipfile; zipfile.ZipFile('/seed/demo-src.zip').extractall('/work')",
            ]
            volumeMounts = [
              { name = "demo-git-src", mountPath = "/seed", readOnly = true },
              { name = "demo-src", mountPath = "/work" },
            ]
          },
          {
            name  = "seed-demo-git"
            image = "alpine/git:2.45.2"
            command = [
              "sh",
              "-c",
              <<-EOT
                set -eu
                export HOME=/tmp
                cd /work
                git init -b main
                git add -A
                git -c user.email=demo@local -c user.name=demo commit -m "local demo snapshot"
                rm -rf /git/demo.git
                git clone --bare /work /git/demo.git
                chown -R 999:999 /git /work || true
              EOT
            ]
            volumeMounts = [
              { name = "demo-src", mountPath = "/work" },
              { name = "demo-git", mountPath = "/git" },
            ]
          },
        ]
        volumes = [
          {
            name = "demo-git-src"
            configMap = {
              name = kubernetes_config_map.demo_git_src.metadata[0].name
            }
          },
          { name = "demo-src", emptyDir = {} },
          { name = "demo-git", emptyDir = {} },
        ]
        volumeMounts = [
          { name = "demo-git", mountPath = "/git" },
        ]
      }
    })
  ]

  depends_on = [kubernetes_config_map.demo_git_src]
}

resource "terraform_data" "workloads" {
  triggers_replace = [
    sha256(templatefile("${path.module}/applicationset-workloads.yaml.tftpl", {
      repo_url      = local.demo_git_url
      repo_revision = local.demo_git_revision
    })),
    data.archive_file.demo_src.output_sha,
  ]

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command = <<-EOT
      cat <<'MANIFEST' | kubectl --context ${var.kube_context} apply -f -
      ${templatefile("${path.module}/applicationset-workloads.yaml.tftpl", {
    repo_url      = local.demo_git_url
    repo_revision = local.demo_git_revision
})}
      MANIFEST
    EOT
}

depends_on = [helm_release.argocd]
}

resource "terraform_data" "databases" {
  triggers_replace = [
    sha256(templatefile("${path.module}/applicationset-databases.yaml.tftpl", {
      repo_url      = local.demo_git_url
      repo_revision = local.demo_git_revision
    })),
    data.archive_file.demo_src.output_sha,
  ]

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command = <<-EOT
      cat <<'MANIFEST' | kubectl --context ${var.kube_context} apply -f -
      ${templatefile("${path.module}/applicationset-databases.yaml.tftpl", {
    repo_url      = local.demo_git_url
    repo_revision = local.demo_git_revision
})}
      MANIFEST
    EOT
}

depends_on = [helm_release.argocd]
}
