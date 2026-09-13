data "aws_partition" "current" {}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter_name
}

locals {
  tags = merge(var.tags, {
    Name = var.name
  })

  # Keep EC2 creation map-driven so the module can grow from the current
  # single-node profile without changing the resource model from count/singleton
  # addresses later. The primary entry preserves the existing node name.
  instances = {
    for key, instance in var.instances : key => {
      name = coalesce(
        try(instance.name, null),
        key == var.primary_instance_key ? var.name : "${var.name}-${key}",
      )
      instance_type    = coalesce(try(instance.instance_type, null), var.instance_type)
      subnet_id        = coalesce(try(instance.subnet_id, null), var.subnet_id)
      root_volume_size = coalesce(try(instance.root_volume_size, null), var.root_volume_size)
      tags             = coalesce(try(instance.tags, null), {})
    }
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
  for_each = local.instances

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
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # The node sits in a public subnet with no NAT gateway, so it needs a public
  # address at launch for user data to reach the internet. The subnet also
  # auto-assigns one, and hardcoding false here made every plan replace the
  # instance. The per-node EIP below then takes over as the stable endpoint.
  associate_public_ip_address = var.associate_public_ip_address

  # Guards against accidental deletion from the console, the CLI, and Terraform
  # itself. Both flags must be cleared before the node can be replaced or
  # destroyed, which is the intended friction.
  disable_api_termination = var.enable_termination_protection
  disable_api_stop        = var.enable_stop_protection

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  # Node configuration is delivered at first boot. Replacing the instance when
  # the script changes keeps the running node identical to the committed
  # bootstrap rather than leaving drift behind.
  user_data                   = var.user_data == "" ? null : var.user_data
  user_data_replace_on_change = var.user_data_replace_on_change

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1

    # Lets the bootstrap read the PublicIp tag below through IMDS.
    instance_metadata_tags = "enabled"
  }

  # The Elastic IP is allocated before the instance exists, so its address is
  # published as a tag. The bootstrap prefers it over IMDS public-ipv4, which
  # reports the launch-time address until the EIP association completes and
  # would otherwise race its way into the API TLS SANs and the kubeconfig.
  tags = merge(local.tags, each.value.tags, {
    Name     = each.value.name
    PublicIp = aws_eip.this[each.key].public_ip
  })

  # Ensure SSM permissions exist before instances boot and register.
  depends_on = [aws_iam_role_policy_attachment.ssm]
}

resource "aws_eip_association" "this" {
  for_each = local.instances

  instance_id   = aws_instance.this[each.key].id
  allocation_id = aws_eip.this[each.key].id
}
