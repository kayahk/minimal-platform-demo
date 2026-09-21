variable "chart_version" {
  type    = string
  default = "0.9.1"
}

variable "targets" {
  type = list(object({
    namespace       = string
    service_account = string
    vault_role      = string
  }))
}
