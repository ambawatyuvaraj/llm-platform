data "aws_ami" "ubuntu_22" {

  most_recent = true
  owners      = ["099720109477"] #this is canonical's official aws account id

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] #dynamic lookup
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

}