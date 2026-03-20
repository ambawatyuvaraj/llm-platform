resource "aws_vpc" "main" {

  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "llm-platform-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "llm-platform-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public_rt" {

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "llm-platform-public-rt"
  }

}

resource "aws_subnet" "public_subnet" {

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "llm-platform-public-subnet"
    Environment = var.environment
  }

}

resource "aws_route_table_association" "public" {

  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id

}


resource "aws_security_group" "k3s-sg" {
  name        = "k3s-cluster-sg"
  description = "k3s cluster security group"
  vpc_id      = aws_vpc.main.id


  tags = {
    Name        = "k3s-cluster-sg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "SSH From operator IP Only - not open to internet"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.my_ip_cidr

}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "HTTP for let;s encrypt"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "HTTPS public vLLM API"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

}

resource "aws_vpc_security_group_ingress_rule" "k3s_api_vpc" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "k3s API Server - VPC INTERNAL ONLY. (worker join + kubectl)"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"

}

resource "aws_vpc_security_group_ingress_rule" "k3s_api_operator" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "k3s API Server (kubectl access) from operator laptop"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.my_ip_cidr

}

resource "aws_vpc_security_group_ingress_rule" "kubelet" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "Kubelet - VPC INTERNAL ONLY."
  from_port         = 10250
  to_port           = 10250
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"

}

resource "aws_vpc_security_group_ingress_rule" "flannel_vxlan" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "Flannel VXLAN overlay  - VPC INTERNAL ONLY."
  from_port         = 8472
  to_port           = 8472
  ip_protocol       = "udp"
  cidr_ipv4         = "10.0.0.0/16"

}

resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "Kubernetes NodePort Range."
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"

}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.k3s-sg.id
  description       = "Allow all outbound traffic."
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

}
