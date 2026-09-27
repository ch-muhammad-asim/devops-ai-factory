data "aws_partition" "current" {}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter_name
}

# K3s servers and agents need the same join token. Terraform owns the generated
# value so it remains stable across plans/applies for the lifetime of this state.
# The token is substituted into the rendered per-node user data below and is not
# exposed as a module output.
resource "random_password" "k3s_cluster_token" {
  length  = 64
  special = false
}

locals {
  tags = merge(var.tags, {
    Name = var.name
  })

  k3s_cluster_token = var.k3s_cluster_token != null ? var.k3s_cluster_token : random_password.k3s_cluster_token.result

  # EC2 creation remains map-driven. Each node can override its private address
  # and bootstrap while inheriting the shared defaults.
  instances = {
    for key, instance in var.instances : key => {
      name = coalesce(
        try(instance.name, null),
        key == var.primary_instance_key ? var.name : "${var.name}-${key}",
      )
      instance_type    = coalesce(try(instance.instance_type, null), var.instance_type)
      subnet_id        = coalesce(try(instance.subnet_id, null), var.subnet_id)
      private_ip       = try(instance.private_ip, null)
      allocate_eip     = try(instance.allocate_eip, true)
      root_volume_size = coalesce(try(instance.root_volume_size, null), var.root_volume_size)
      user_data        = try(instance.user_data, null) != null ? instance.user_data : var.user_data
      tags             = coalesce(try(instance.tags, null), {})
    }
  }

  eip_instances = {
    for key, instance in local.instances : key => instance
    if instance.allocate_eip
  }
}

# Preserve existing singleton state addresses when upgrading an already-applied
# environment to the for_each resource model.
moved {
  from = aws_eip.this
  to   = aws_eip.this["primary"]
}

moved {
  from = aws_instance.this
  to   = aws_instance.this["primary"]
}

moved {
  from = aws_eip_association.this
  to   = aws_eip_association.this["primary"]
}

resource "aws_eip" "this" {
  for_each = local.eip_instances

  domain = "vpc"

  tags = merge(local.tags, each.value.tags, {
    Name = "${each.value.name}-eip"
  })
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = var.additional_iam_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-profile"
  role = aws_iam_role.this.name
  tags = local.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "Security group for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  cidr_ipv4         = each.value.cidr_ipv4
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
}

# K3s needs multiple east-west ports for the API, embedded etcd, kubelet and
# CNI traffic. Restricting this rule to the same security group keeps those
# cluster-internal protocols private without publishing them to the internet.
resource "aws_vpc_security_group_ingress_rule" "cluster_internal" {
  count = var.allow_cluster_internal_traffic ? 1 : 0

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = aws_security_group.this.id
  description                  = "All traffic between K3s cluster nodes"
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "this" {
  for_each = local.instances

  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = each.value.instance_type
  subnet_id              = each.value.subnet_id
  private_ip             = each.value.private_ip
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # The node sits in a public subnet with no NAT gateway, so it needs a public
  # address at launch for user data to reach the internet. The per-node EIP
  # then takes over as the stable public address.
  associate_public_ip_address = var.associate_public_ip_address

  disable_api_termination = var.enable_termination_protection
  disable_api_stop        = var.enable_stop_protection

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  # A node-specific bootstrap can be supplied in var.instances. The generated
  # K3s join token replaces only this explicit placeholder, keeping the token
  # stable while allowing each instance to have a different server/agent role.
  user_data = each.value.user_data == "" ? null : replace(
    each.value.user_data,
    "__K3S_CLUSTER_TOKEN__",
    local.k3s_cluster_token,
  )
  user_data_replace_on_change = var.user_data_replace_on_change

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1

    instance_metadata_tags = "enabled"
  }

  tags = merge(
    local.tags,
    each.value.tags,
    {
      Name = each.value.name
    },
    each.value.allocate_eip ? {
      PublicIp = aws_eip.this[each.key].public_ip
    } : {},
  )

  depends_on = [aws_iam_role_policy_attachment.ssm]
}

resource "aws_eip_association" "this" {
  for_each = local.eip_instances

  instance_id   = aws_instance.this[each.key].id
  allocation_id = aws_eip.this[each.key].id
}
