variable "chart_version" {
  type    = string
  default = "0.29.0"
}

variable "enable_custom_resources" {
  type        = bool
  default     = true
  description = "Whether to create resources whose kinds are supplied by installed operators."
}
