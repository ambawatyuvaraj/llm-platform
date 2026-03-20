resource "aws_instance" "k3s_nodes" {
  count = var.node_count

  ami                    = data.aws_ami.ubuntu_22.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k3s-sg.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.vault_kms.name


  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  tags = {
    Name        = "k3s-node-${count.index}"
    Role        = count.index == 0 ? "control-plane" : "worker"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

}