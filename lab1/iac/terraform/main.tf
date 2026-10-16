terraform {
  required_version = "1.16.4"

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

variable "kdg_username" {
  description = "Cognito username for Kinesis Data Generator"
  type        = string
  default     = "aws-datalake"
}

variable "kdg_password" {
  description = "Cognito password for Kinesis Data Generator (min 6 alphanumeric chars, at least one number)"
  type        = string
  default     = "password12"
  sensitive   = true
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── Pre-existing resources created by admin (iam-freeconciled.json CFn stack) ─

data "aws_s3_bucket" "sdl" {
  bucket = "sdl-immersion-day-${data.aws_caller_identity.current.account_id}"
}

data "aws_iam_role" "glue" {
  name = "SDL-GlueRole"
}

data "aws_iam_role" "firehose" {
  name = "SDL-FirehoseRole"
}

# ─── Kinesis Firehose Delivery Stream ────────────────────────────────────────

resource "aws_kinesis_firehose_delivery_stream" "sdl" {
  name        = "sdl-firehose-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = data.aws_iam_role.firehose.arn
    bucket_arn          = data.aws_s3_bucket.sdl.arn
    prefix              = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "error/"
    buffering_size      = 1
    buffering_interval  = 60
    compression_format  = "GZIP"
  }
}

# ─── Stack 2: SDL-Cognito-Setup via CloudFormation ───────────────────────────
# Deploying via CloudFormation so IAM roles are created with the SDL-KDG-Boundary
# permissions boundary, satisfying the participant guardrails policy conditions.

resource "aws_cloudformation_stack" "kdg_cognito" {
  name          = "Kinesis-Data-Generator-Cognito-User"
  template_body = file("${path.module}/../cfn/02-cognito-setup.yaml")
  capabilities  = ["CAPABILITY_IAM"]

  parameters = {
    Username               = var.kdg_username
    Password               = var.kdg_password
    PermissionsBoundaryArn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/SDL-KDG-Boundary"
  }

}

# ─── Cognito User ────────────────────────────────────────────────────────────

resource "aws_cognito_user" "kdg" {
  user_pool_id = aws_cloudformation_stack.kdg_cognito.outputs["UserPoolId"]
  username     = var.kdg_username
  password     = var.kdg_password

  message_action = "SUPPRESS"

  attributes = {
    email          = "${var.kdg_username}@example.com"
    email_verified = true
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "s3_bucket_name" {
  value = data.aws_s3_bucket.sdl.bucket
}

output "glue_role_arn" {
  value = data.aws_iam_role.glue.arn
}

output "firehose_role_arn" {
  value = data.aws_iam_role.firehose.arn
}

output "firehose_stream_arn" {
  value = aws_kinesis_firehose_delivery_stream.sdl.arn
}

output "kdg_url" {
  description = "Kinesis Data Generator URL"
  value       = aws_cloudformation_stack.kdg_cognito.outputs["KinesisDataGeneratorUrl"]
}

output "kdg_secret_arn" {
  description = "SecretsManager secret storing the KDG Cognito credentials"
  value       = aws_cloudformation_stack.kdg_cognito.outputs["KinesisDataGeneratorCognitoUser"]
}
