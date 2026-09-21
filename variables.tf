variable "enable_custom_resources" {
  type        = bool
  default     = true
  description = "Whether to create resources whose kinds are supplied by installed operators."
}

variable "kube_context" {
  type        = string
  default     = "kind-platform-demo"
  description = "kubectl context created by scripts/up.sh"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "repo_url" {
  type        = string
  default     = "https://github.com/kayahk/minimal-platform-demo.git"
  description = "Git URL the ApplicationSet clones. Forks should override this."
}

variable "repo_revision" {
  type    = string
  default = "main"
}
