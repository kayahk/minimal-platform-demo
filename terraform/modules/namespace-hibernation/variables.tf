variable "namespaces" {
  type = map(object({
    hibernate   = bool
    project     = string
    service     = string
    environment = string
  }))
}

variable "chart_version" {
  type    = string
  default = "1.3.4"
}

variable "uptime" {
  type        = string
  default     = "Mon-Fri 08:00-18:00 UTC"
  description = "Schedule applied to namespaces with hibernate=true. Outside this window GoKubeDownscaler scales those workloads to zero."
}
