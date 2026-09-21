variable "kube_context" {
  type    = string
  default = "kind-platform-demo"
}

variable "chart_version" {
  type    = string
  default = "7.8.23"
}

variable "repo_url" {
  type = string
}

variable "repo_revision" {
  type    = string
  default = "main"
}
