# K3s itself is installed by the EC2 user data rendered in the compute layer, so
# this unit owns only the operator-facing side of the cluster: retrieving the
# kubeconfig onto the machine running Terragrunt and exposing the client
# material to the downstream Helm units.
locals {
  kubeconfig_path = var.kubeconfig_path != "" ? var.kubeconfig_path : pathexpand("~/.kube/${var.cluster_name}.yaml")
}

# The node publishes its kubeconfig at a fixed path during boot. Systems Manager
# is used purely as a transport here, which keeps the workflow free of SSH keys,
# bastions, and inbound access to port 22.
resource "terraform_data" "kubeconfig" {
  triggers_replace = [
    var.instance_id,
    var.public_ip,
    local.kubeconfig_path,
  ]

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      REGION="${var.region}"
      INSTANCE="${var.instance_id}"
      DEST="${local.kubeconfig_path}"
      DEADLINE=$((SECONDS + ${var.kubeconfig_timeout_seconds}))

      mkdir -p "$(dirname "$DEST")"

      while [ "$SECONDS" -lt "$DEADLINE" ]; do
        COMMAND_ID="$(aws ssm send-command \
          --region "$REGION" \
          --instance-ids "$INSTANCE" \
          --document-name AWS-RunShellScript \
          --parameters 'commands=["cat /etc/rancher/k3s/k3s-public.yaml"]' \
          --query Command.CommandId \
          --output text 2>/dev/null || true)"

        if [ -n "$COMMAND_ID" ]; then
          for _ in $(seq 1 30); do
            STATUS="$(aws ssm get-command-invocation \
              --region "$REGION" \
              --command-id "$COMMAND_ID" \
              --instance-id "$INSTANCE" \
              --query Status \
              --output text 2>/dev/null || echo Pending)"

            case "$STATUS" in
              Success)
                aws ssm get-command-invocation \
                  --region "$REGION" \
                  --command-id "$COMMAND_ID" \
                  --instance-id "$INSTANCE" \
                  --query StandardOutputContent \
                  --output text > "$DEST"
                chmod 600 "$DEST"
                echo "[k3s] kubeconfig written to $DEST"
                exit 0
                ;;
              Pending|InProgress|Delayed)
                sleep 2
                ;;
              *)
                break
                ;;
            esac
          done
        fi

        echo "[k3s] waiting for the node to finish bootstrapping"
        sleep 10
      done

      echo "[k3s] timed out waiting for the kubeconfig on $INSTANCE" >&2
      exit 1
    EOT
  }
}

# Reading the file only after the provisioner has run keeps the fetch and the
# Helm provider credentials inside a single apply.
data "local_file" "kubeconfig" {
  filename = local.kubeconfig_path

  depends_on = [terraform_data.kubeconfig]
}
