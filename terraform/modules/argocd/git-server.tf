locals {
  repo_root         = abspath("${path.root}/..")
  demo_git_url      = "file:///git/demo.git"
  demo_git_revision = "main"
  demo_git_files = merge(
    { for f in fileset("${local.repo_root}/registry", "**") : "registry/${f}" => file("${local.repo_root}/registry/${f}") },
    { for f in fileset("${local.repo_root}/charts", "**") : "charts/${f}" => file("${local.repo_root}/charts/${f}") },
    { for f in fileset("${local.repo_root}/apps", "**") : "apps/${f}" => file("${local.repo_root}/apps/${f}") },
  )
}

data "archive_file" "demo_src" {
  type        = "zip"
  output_path = "${path.root}/.terraform/demo-src.zip"

  dynamic "source" {
    for_each = local.demo_git_files
    content {
      filename = source.key
      content  = source.value
    }
  }
}

resource "kubernetes_config_map" "demo_git_src" {
  metadata {
    name      = "demo-git-src"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  binary_data = {
    "demo-src.zip" = filebase64(data.archive_file.demo_src.output_path)
  }
}
