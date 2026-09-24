terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" { type = string, default = "us-east-1" }
variable "bucket_name" { type = string }

provider "aws" { region = var.aws_region }

resource "aws_s3_bucket" "pipeline" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "pipeline" {
  bucket                  = aws_s3_bucket.pipeline.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  rule {
    id     = "expire-demo-files"
    status = "Enabled"
    filter { prefix = "raw/" }
    expiration { days = 30 }
  }
}

output "bucket_name" { value = aws_s3_bucket.pipeline.id }
output "raw_prefix" { value = "s3://${aws_s3_bucket.pipeline.id}/raw/" }
