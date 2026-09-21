resource "kubernetes_namespace" "stage" {
  for_each = var.namespaces

  metadata {
    name = each.key
    labels = {
      "platform.demo/project"     = each.value.project
      "platform.demo/service"     = each.value.service
      "platform.demo/environment" = each.value.environment
    }
    annotations = each.value.hibernate ? {
      "downscaler/uptime" = "Mon-Fri 08:00-18:00 Europe/Berlin"
    } : {}
  }
}
