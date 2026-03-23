output "control_plane_ip" {
  description = "Public IP of k3s control plane"
  value       = aws_instance.k3s_nodes[0].public_ip

}

output "worker_ips" {
  description = "Public IPs of all worker nodes"
  value       = slice(aws_instance.k3s_nodes[*].public_ip, 1, var.node_count)

}

output "all_node_ips" {
  description = "Public IPs of all nodes"
  value       = aws_instance.k3s_nodes[*].public_ip

}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id

}

output "control_plane_private_ip" {
  description = "Private IP of control plane used by workers to join via VPC internal address."
  value = aws_instance.k3s_nodes[0].private_ip
  
}

output "vault_kms_key_id" {
  description = "KMS key ID for vault auto unseal (we'll be using this in configure-vault.sh script)"
  value       = aws_kms_key.vault_unseal.key_id

}