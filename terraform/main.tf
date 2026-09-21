locals {
  repo_root = abspath("${path.module}/..")

  configs = {
    for f in fileset("${local.repo_root}/registry", "**/config.json") :
    trimsuffix(f, "/config.json") => jsondecode(file("${local.repo_root}/registry/${f}"))
  }

  targets = flatten([
    for path, cfg in local.configs : [
      for env in cfg.spec.environments : {
        path            = path
        project         = cfg.projectName
        service         = cfg.serviceName
        environment     = env.name
        namespace       = "${cfg.projectName}-${env.name}"
        service_account = "${cfg.projectName}-${cfg.serviceName}-sa"
        vault_role      = "${cfg.projectName}-${cfg.serviceName}"
        vault_policy    = "${cfg.projectName}-${cfg.serviceName}-access"
        hibernate       = try(env.hibernate, false)
        vault_operator  = try(cfg.vaultOperator, false)
        has_database    = try(cfg.spec.database, null) != null
      }
    ]
  ])

  namespaces = {
    for t in local.targets : t.namespace => {
      hibernate   = t.hibernate
      project     = t.project
      service     = t.service
      environment = t.environment
    }
  }

  vault_targets = [for t in local.targets : t if t.vault_operator]
}

module "kyverno" {
  source = "./modules/kyverno"
}

module "cnpg_operator" {
  source                  = "./modules/cnpg-operator"
  enable_custom_resources = var.enable_custom_resources
  database_targets = [
    for t in local.targets : {
      namespace   = t.namespace
      project     = t.project
      service     = t.service
      environment = t.environment
    } if t.has_database
  ]

  depends_on = [module.namespace_hibernation]
}

module "vault" {
  source  = "./modules/vault"
  targets = local.vault_targets
}

module "namespace_hibernation" {
  source     = "./modules/namespace-hibernation"
  namespaces = local.namespaces
  uptime     = "Mon-Fri 08:00-18:00 ${var.host_timezone}"
}

module "vault_secrets_operator" {
  source                  = "./modules/vault-secrets-operator"
  enable_custom_resources = var.enable_custom_resources
  targets                 = local.vault_targets

  depends_on = [
    module.vault,
    module.namespace_hibernation,
  ]
}

module "argocd" {
  source        = "./modules/argocd"
  kube_context  = var.kube_context
  repo_url      = var.repo_url
  repo_revision = var.repo_revision

  depends_on = [
    module.cnpg_operator,
    module.namespace_hibernation,
  ]
}
