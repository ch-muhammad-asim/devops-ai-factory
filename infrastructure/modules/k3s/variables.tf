variable "cluster_name" {
  description = "K3s cluster/node name."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "instance_id" {
  description = "EC2 instance ID running K3s. The node is bootstrapped by user data in the compute layer."
  type        = string
}

variable "public_ip" {
  description = "Stable public IP serving the K3s API. Changing it refreshes the local kubeconfig."
  type        = string
}

variable "k3s_version" {
  description = "Exact K3s release installed by the node bootstrap. Recorded here so the deployed version is visible in state and outputs."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be an exact K3s release such as v1.36.4+k3s1."
  }
}

variable "kubeconfig_path" {
  description = "Local path the cluster kubeconfig is written to. Defaults to ~/.kube/<cluster_name>.yaml."
  type        = string
  default     = ""
}

variable "kubeconfig_timeout_seconds" {
  description = "Maximum time to wait for the node bootstrap to publish a kubeconfig."
  type        = number
  default     = 900

  validation {
    condition     = var.kubeconfig_timeout_seconds >= 60
    error_message = "kubeconfig_timeout_seconds must be at least 60 seconds."
  }
}

variable "tags" {
  description = "Common tags passed by Terragrunt."
  type        = map(string)
  default     = {}
}
