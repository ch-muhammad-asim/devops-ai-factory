variable "name" {
  description = "Base name used for EC2 nodes and supporting resources."
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

variable "vpc_id" {
  description = "VPC ID for the EC2 security group."
  type        = string
}

variable "subnet_id" {
  description = "Default subnet ID used by EC2 instances unless overridden per instance."
  type        = string
}

variable "instance_type" {
  description = "Default EC2 instance type used unless overridden per instance."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Default root EBS volume size in GiB used unless overridden per instance."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}

variable "primary_instance_key" {
  description = "Key in var.instances exposed through the backwards-compatible singular outputs consumed by the current K3s unit."
  type        = string
  default     = "primary"
}

variable "instances" {
  description = "Map of EC2 nodes created with for_each. Optional values inherit the module-level defaults."
  type = map(object({
    name             = optional(string)
    instance_type    = optional(string)
    subnet_id        = optional(string)
    root_volume_size = optional(number)
    tags             = optional(map(string), {})
  }))

  default = {
    primary = {}
  }

  validation {
    condition = alltrue([
      for instance in values(var.instances) :
      instance.root_volume_size == null ? true : instance.root_volume_size >= 20
    ])
    error_message = "Each per-instance root_volume_size override must be at least 20 GiB."
  }
}

variable "ami_ssm_parameter_name" {
  description = "Canonical AWS SSM public parameter containing the Ubuntu Server 26.04 LTS AMD64 gp3 AMI ID. Override when a different OS/release or architecture is intentionally required."
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

variable "ingress_rules" {
  description = "IPv4 ingress rules applied to the shared EC2 node security group."
  type = map(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_ipv4   = string
  }))
  default = {}
}

variable "additional_iam_policy_arns" {
  description = "Additional managed IAM policies to attach to the shared EC2 instance role."
  type        = set(string)
  default     = []
}

variable "associate_public_ip_address" {
  description = "Assign a public IP at launch. Required in a public subnet without a NAT gateway, and must match the subnet's auto-assign setting to avoid a permanent replacement diff."
  type        = bool
  default     = true
}

variable "enable_termination_protection" {
  description = "Enable EC2 API termination protection. Must be turned off before the instance can be replaced or destroyed."
  type        = bool
  default     = false
}

variable "enable_stop_protection" {
  description = "Enable EC2 API stop protection so the node cannot be stopped accidentally."
  type        = bool
  default     = false
}

variable "user_data" {
  description = "Cloud-init user data executed on first boot. Empty disables user data entirely."
  type        = string
  default     = ""
}

variable "user_data_replace_on_change" {
  description = "Replace the instance when user data changes so a rendered bootstrap is never left stale on a running node."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common AWS tags."
  type        = map(string)
  default     = {}
}
