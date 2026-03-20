resource "aws_iam_role" "vault_kms" {
  name = "vault-kms-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"
    Statement = [{
      Effect    = "ALlow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name      = "vault-kms-role"
    ManagedBy = "terraform"
  }

}

resource "aws_iam_role_policy" "vault_kms" {
  name = "vault-kms-policy"
  role = aws_iam_role.vault_kms.id

  policy = jsonencode({

    Version = "2012-10-17"
    Statement = [{
      Sid      = "VaultKMSUnseal"
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      Resrouce = aws_kms_key.vault_unseal.arn
    }]
  })

}


#iam instance profile to attach the role to ec2
resource "aws_iam_instance_profile" "vault_kms" {
  name = "vault-kms-instance-profile"
  role = aws_iam_role.vault_kms.name

}