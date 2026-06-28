terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "app"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "public_key" {
  description = "SSH public key material"
  type        = string
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

# Amazon Linux 2023 AMI (x86_64)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Key pair
# ---------------------------------------------------------------------------

resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key

  tags = {
    Project = var.project_name
  }
}

# ---------------------------------------------------------------------------
# Networking - default VPC / subnets
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH and HTTP inbound"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
    Name    = "${var.project_name}-sg"
  }
}

# ---------------------------------------------------------------------------
# EC2 instance
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.app.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Project = var.project_name
    Name    = "${var.project_name}-instance"
  }
}

# ---------------------------------------------------------------------------
# Elastic IP - stable public address
# ---------------------------------------------------------------------------

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Project = var.project_name
    Name    = "${var.project_name}-eip"
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "instance_public_ip" {
  description = "Static public IP of the EC2 instance"
  value       = aws_eip.app.public_ip
}

output "app_url" {
  description = "Public HTTP URL of the application"
  value       = "http://${aws_eip.app.public_ip}"
}

output "ssh_connection" {
  description = "SSH connection string"
  value       = "ssh -i <private_key> ec2-user@${aws_eip.app.public_ip}"
}