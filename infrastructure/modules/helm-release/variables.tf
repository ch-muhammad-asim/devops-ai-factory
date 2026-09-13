variable "environment" {
  description = "Environment name passed by the Terragrunt root configuration."
  type        = string
}

variable "region" {
  description = "AWS region passed by the Terragrunt root configuration."
  type        = string
}

variable "tags" {
  description = "Common tags passed by Terragrunt for a consistent module interface."
  type        = map(string)
  default     = {}
}

variable "release_name" {
  description = "Helm release name."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the release."
  type        = string
}

variable "repository" {
  description = "Upstream Helm repository URL."
  type        = string
}

variable "chart" {
  description = "Upstream Helm chart name."
  type        = string
}

variable "chart_version" {
  description = "Exact Helm chart version."
  type        = string
}

variable "values_yaml" {
  description = "Raw YAML passed to the upstream chart."
  type        = string
  default     = ""
}

variable "create_namespace" {
  description = "Create the Kubernetes namespace when it does not exist."
  type        = bool
  default     = true
}

variable "timeout_seconds" {
  description = "Maximum Helm operation timeout."
  type        = number
  default     = 600
}

variable "kubernetes_host" {
  description = "Kubernetes API endpoint."
  type        = string
}

variable "cluster_ca_certificate_data" {
  description = "Base64-encoded Kubernetes CA certificate."
  type        = string
  sensitive   = true
}

variable "client_certificate_data" {
  description = "Base64-encoded Kubernetes client certificate."
  type        = string
  sensitive   = true
}

variable "client_key_data" {
  description = "Base64-encoded Kubernetes client private key."
  type        = string
  sensitive   = true
}
