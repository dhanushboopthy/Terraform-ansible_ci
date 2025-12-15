terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  os_name         = "ubuntu"
  instance_prefix = "${local.os_name}-ec2"
  instance_name   = "${local.instance_prefix}-${var.environment}"
  common_tags = {
    Name        = local.instance_name
    Environment = var.environment
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_key_pair" "ansible_key" {
  key_name   = "ansible-key-${var.environment}"
  public_key = file(var.public_key_path)
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg-${var.environment}"
  description = "Basic SSH access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_instance" "ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.ansible_key.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = local.common_tags
}

# Generate dynamic inventory for Ansible
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    ec2_ip      = aws_instance.ec2.public_ip
    ssh_user    = "ubuntu"
    private_key = var.private_key_path
  })
  filename = "${path.module}/../ansible/inventory.ini"
}