resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto unseal (pod restarts automatically)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "vault-unseal-key"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id

}