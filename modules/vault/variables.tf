variable "chart_version" {
  type    = string
  default = "0.29.1"
}

variable "root_token" {
  type      = string
  default   = "root"
  sensitive = true
}

variable "targets" {
  description = "Flattened registry environments used to derive Vault roles and policies."
  type = list(object({
    project         = string
    service         = string
    environment     = string
    namespace       = string
    service_account = string
    vault_role      = string
    vault_policy    = string
  }))
}
