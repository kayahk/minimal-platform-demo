variable "namespaces" {
  type = map(object({
    hibernate   = bool
    project     = string
    service     = string
    environment = string
  }))
}
