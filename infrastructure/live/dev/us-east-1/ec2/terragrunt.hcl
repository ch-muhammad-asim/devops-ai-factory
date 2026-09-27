include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "component" {
  path           = "${dirname(find_in_parent_folders("root.hcl"))}/_common/ec2.hcl"
  merge_strategy = "deep"
}

locals {
  region_dir = dirname(find_in_parent_folders("region.hcl"))

  operator_cidr = get_env(
    "TG_OPERATOR_CIDR",
    "${trimspace(run_cmd("--terragrunt-quiet", "curl", "-fsS", "https://checkip.amazonaws.com"))}/32",
  )

  k3s_config = read_terragrunt_config(
    "${get_repo_root()}/infrastructure/live/_common/k3s.hcl",
  )

  bootstrap_template          = "${get_repo_root()}/infrastructure/templates/k3s-install.sh.tftpl"
  bootstrap_server_private_ip = "10.20.1.10"
  bootstrap_server_url        = "https://${local.bootstrap_server_private_ip}:6443"
  expected_node_count         = 5
}

dependency "vpc" {
  config_path = "${local.region_dir}/vpc"

  mock_outputs = {
    vpc_id            = "vpc-00000000000000000"
    public_subnet_ids = ["subnet-00000000000000000"]
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  name             = "${include.root.locals.cluster_name}-node"
  vpc_id           = dependency.vpc.outputs.vpc_id
  subnet_id        = dependency.vpc.outputs.public_subnet_ids[0]
  root_volume_size = 100

  # Protect instances from accidental termination. Stop protection remains
  # disabled so nodes can still be stopped during maintenance or lab work.
  enable_termination_protection = true
  enable_stop_protection        = false

  # K3s control-plane, embedded-etcd, kubelet and CNI traffic stays private and
  # is allowed only between instances carrying this shared security group.
  allow_cluster_internal_traffic = true

  # Five-node K3s lab topology:
  #   primary  -> server-1, initializes embedded etcd
  #   server-2 -> joins as a K3s server/control-plane node
  #   server-3 -> joins as a K3s server/control-plane node
  #   worker-1 -> joins as a K3s agent
  #   worker-2 -> joins as a K3s agent
  #
  # Fixed private IPs give every joining node a stable in-VPC bootstrap endpoint
  # without requiring a load balancer for this learning environment.
  instances = {
    primary = {
      name          = "${include.root.locals.cluster_name}-server-1"
      instance_type = "t3a.medium"
      private_ip    = local.bootstrap_server_private_ip
      allocate_eip  = true
      tags = {
        K3sRole  = "server"
        NodeRole = "control-plane"
      }
      user_data = templatefile(local.bootstrap_template, {
        node_name           = "${include.root.locals.cluster_name}-server-1"
        node_role           = "server-init"
        server_url          = ""
        k3s_token           = "__K3S_CLUSTER_TOKEN__"
        expected_node_count = local.expected_node_count
        k3s_version         = local.k3s_config.locals.k3s_version
        traefik_flag        = local.k3s_config.locals.enable_traefik ? "" : "--disable traefik"
      })
    }

    server-2 = {
      name          = "${include.root.locals.cluster_name}-server-2"
      instance_type = "t3a.medium"
      private_ip    = "10.20.1.11"
      allocate_eip  = false
      tags = {
        K3sRole  = "server"
        NodeRole = "control-plane"
      }
      user_data = templatefile(local.bootstrap_template, {
        node_name           = "${include.root.locals.cluster_name}-server-2"
        node_role           = "server"
        server_url          = local.bootstrap_server_url
        k3s_token           = "__K3S_CLUSTER_TOKEN__"
        expected_node_count = local.expected_node_count
        k3s_version         = local.k3s_config.locals.k3s_version
        traefik_flag        = local.k3s_config.locals.enable_traefik ? "" : "--disable traefik"
      })
    }

    server-3 = {
      name          = "${include.root.locals.cluster_name}-server-3"
      instance_type = "t3a.medium"
      private_ip    = "10.20.1.12"
      allocate_eip  = false
      tags = {
        K3sRole  = "server"
        NodeRole = "control-plane"
      }
      user_data = templatefile(local.bootstrap_template, {
        node_name           = "${include.root.locals.cluster_name}-server-3"
        node_role           = "server"
        server_url          = local.bootstrap_server_url
        k3s_token           = "__K3S_CLUSTER_TOKEN__"
        expected_node_count = local.expected_node_count
        k3s_version         = local.k3s_config.locals.k3s_version
        traefik_flag        = local.k3s_config.locals.enable_traefik ? "" : "--disable traefik"
      })
    }

    worker-1 = {
      name          = "${include.root.locals.cluster_name}-worker-1"
      instance_type = "t3a.medium"
      private_ip    = "10.20.1.21"
      allocate_eip  = false
      tags = {
        K3sRole  = "agent"
        NodeRole = "worker"
      }
      user_data = templatefile(local.bootstrap_template, {
        node_name           = "${include.root.locals.cluster_name}-worker-1"
        node_role           = "agent"
        server_url          = local.bootstrap_server_url
        k3s_token           = "__K3S_CLUSTER_TOKEN__"
        expected_node_count = local.expected_node_count
        k3s_version         = local.k3s_config.locals.k3s_version
        traefik_flag        = local.k3s_config.locals.enable_traefik ? "" : "--disable traefik"
      })
    }

    worker-2 = {
      name          = "${include.root.locals.cluster_name}-worker-2"
      instance_type = "t3a.medium"
      private_ip    = "10.20.1.22"
      allocate_eip  = false
      tags = {
        K3sRole  = "agent"
        NodeRole = "worker"
      }
      user_data = templatefile(local.bootstrap_template, {
        node_name           = "${include.root.locals.cluster_name}-worker-2"
        node_role           = "agent"
        server_url          = local.bootstrap_server_url
        k3s_token           = "__K3S_CLUSTER_TOKEN__"
        expected_node_count = local.expected_node_count
        k3s_version         = local.k3s_config.locals.k3s_version
        traefik_flag        = local.k3s_config.locals.enable_traefik ? "" : "--disable traefik"
      })
    }
  }

  ingress_rules = {
    http = {
      description = "HTTP ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }

    https = {
      description = "HTTPS ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }

    kubernetes_api = {
      description = "Kubernetes API from the Terragrunt operator"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_ipv4   = local.operator_cidr
    }
  }
}
