terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Default VPC & Subnets (Virginia / us-east-1)
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

# subnets pinned to specific AZs (a1 / a2 as requested)
data "aws_subnet" "az_a" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "${var.aws_region}a"
  default_for_az    = true
}

data "aws_subnet" "az_b" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "${var.aws_region}b"
  default_for_az    = true
}

# Dynamic, safe subnet selection for the ALB (works no matter how many
# default AZ subnets actually exist in the account/region - avoids
# hardcoding a specific AZ like "c" that might not have a default subnet)
locals {
  alb_subnet_ids = slice(data.aws_subnets.default.ids, 0, min(3, length(data.aws_subnets.default.ids)))
}

# RHEL 9 AMI (official Red Hat account)
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-9*_HVM-*-x86_64*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
