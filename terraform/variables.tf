variable "aws_region" {

  description = "AWS Region"
  type        = string
  default     = "us-east-1"

}

variable "instance_type" {
  default     = "t3.large"
  description = "EC2 Instance type - t3.medium (2vCPU/4GB)"
  type        = string

}

variable "node_count" {
  default     = 3
  type        = number
  description = "Number of k3s nodes we need (1 controlplace, 2 worker nodes)"

}

variable "key_name" {
  type        = string
  default     = "k3s-key"
  description = "AWS KeyPair name"

}

variable "my_ip_cidr" {

  description = "My public ip in cidr notation for ssh access."
  type        = string

}

variable "environment" {
  description = "Environment tag that'll be applied to all resources."
  type        = string
  default     = "dev"

}