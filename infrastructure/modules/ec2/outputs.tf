output "instance_ids" {
  description = "Map of EC2 instance IDs keyed by var.instances."
  value       = { for key, instance in aws_instance.this : key => instance.id }
}

output "public_ips" {
  description = "Map of stable Elastic IPs keyed by var.instances."
  value       = { for key, eip in aws_eip.this : key => eip.public_ip }
}

output "private_ips" {
  description = "Map of EC2 private IPs keyed by var.instances."
  value       = { for key, instance in aws_instance.this : key => instance.private_ip }
}

output "ssm_session_commands" {
  description = "Map of AWS Systems Manager session commands keyed by var.instances."
  value = {
    for key, instance in aws_instance.this :
    key => "aws ssm start-session --region ${var.region} --target ${instance.id}"
  }
}

# Backwards-compatible singular outputs point at primary_instance_key so the
# current single-node K3s unit does not need a state or dependency migration.
output "instance_id" {
  description = "Primary EC2 instance ID."
  value       = aws_instance.this[var.primary_instance_key].id
}

output "public_ip" {
  description = "Stable Elastic IP associated with the primary EC2 instance."
  value       = aws_eip.this[var.primary_instance_key].public_ip
}

output "private_ip" {
  description = "Private IP of the primary EC2 instance."
  value       = aws_instance.this[var.primary_instance_key].private_ip
}

output "security_group_id" {
  description = "Shared EC2 node security group ID."
  value       = aws_security_group.this.id
}

output "iam_role_name" {
  description = "Shared IAM role attached to the EC2 instances."
  value       = aws_iam_role.this.name
}

output "ssm_session_command" {
  description = "Command for opening an SSM shell session to the primary EC2 instance."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.this[var.primary_instance_key].id}"
}
