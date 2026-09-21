variable "enable_custom_resources" {
  type        = bool
  default     = true
  description = "Whether to create resources whose kinds are supplied by installed operators."
}

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
