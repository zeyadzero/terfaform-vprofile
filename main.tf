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

# Dynamic, safe subnet selection - doesn't assume specific AZs (like "a"/"b"/"c")
# actually have a default subnet in this account. Falls back gracefully if the
# account only has one default subnet.
locals {
  default_subnet_ids = data.aws_subnets.default.ids
  tomcat1_subnet_id   = local.default_subnet_ids[0]
  tomcat2_subnet_id   = length(local.default_subnet_ids) > 1 ? local.default_subnet_ids[1] : local.default_subnet_ids[0]
  alb_subnet_ids      = slice(local.default_subnet_ids, 0, min(3, length(local.default_subnet_ids)))
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
