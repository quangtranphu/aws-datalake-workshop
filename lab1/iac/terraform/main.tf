terraform {
  required_version = "~> 1.15"

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
data "aws_partition" "current" {}

# ─── Stack 1: SDL-Service-Roles (cfn.json) ───────────────────────────────────

resource "aws_s3_bucket" "sdl" {
  bucket = "sdl-immersion-day-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "sdl" {
  bucket = aws_s3_bucket.sdl.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "glue" {
  name = "SDL-GlueRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_interactive_sessions" {
  name = "AWSGlueInteractiveSessions"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = aws_iam_role.glue.arn
      Condition = {
        StringLike = { "iam:PassedToService" = "glue.amazonaws.com" }
      }
    }]
  })
}

resource "aws_iam_role" "firehose" {
  name = "SDL-FirehoseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = ""
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

}

resource "aws_iam_role_policy_attachment" "firehose_cloudwatch" {
  role       = aws_iam_role.firehose.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy" "s3_access" {
  name = "S3BucketPermissions"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.sdl.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy" "firehose_s3_access" {
  name = "S3BucketPermissions"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.sdl.arn}/*"
    }]
  })
}

# ─── Stack 2: SDL-Cognito-Setup (cognito-setup.yaml) ─────────────────────────

resource "aws_secretsmanager_secret" "kdg" {
  name        = "KinesisDataGeneratorUser"
  description = "Secret for the Cognito User for the Kinesis Data Generator"
}

resource "aws_secretsmanager_secret_version" "kdg" {
  secret_id     = aws_secretsmanager_secret.kdg.id
  secret_string = jsonencode({ username = var.kdg_username, password = var.kdg_password })
}

resource "aws_iam_role" "kdg_lambda_exec" {
  name = "KDG-SetupLambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "kdg_lambda_exec_policy" {
  name = "SetupCognitoLambda"
  role = aws_iam_role.kdg_lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:*:log-group:/aws/lambda/KinesisDataGeneratorCognitoSetup*"
      },
      {
        Effect   = "Allow"
        Action   = ["cognito-idp:AdminConfirmSignUp", "cognito-idp:CreateUserPoolClient", "cognito-idp:AdminCreateUser"]
        Resource = "arn:${data.aws_partition.current.partition}:cognito-idp:*:*:userpool/*"
      },
      {
        Effect   = "Allow"
        Action   = ["cognito-idp:CreateUserPool", "cognito-identity:CreateIdentityPool", "cognito-identity:SetIdentityPoolRoles"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:UpdateAssumeRolePolicy", "iam:PassRole"]
        Resource = [aws_iam_role.kdg_auth.arn, aws_iam_role.kdg_unauth.arn]
      }
    ]
  })
}

resource "aws_iam_role" "kdg_auth" {
  name = "KDG-AuthenticatedUserRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.kdg.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "authenticated"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "kdg_auth_policy" {
  name = "AllowStreaming"
  role = aws_iam_role.kdg_auth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kinesis:DescribeStream", "kinesis:PutRecord", "kinesis:PutRecords"]
        Resource = "arn:${data.aws_partition.current.partition}:kinesis:*:*:stream/*"
      },
      {
        Effect   = "Allow"
        Action   = ["firehose:DescribeDeliveryStream", "firehose:PutRecord", "firehose:PutRecordBatch"]
        Resource = "arn:${data.aws_partition.current.partition}:firehose:*:*:deliverystream/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeRegions", "firehose:ListDeliveryStreams", "kinesis:ListStreams"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "kdg_unauth" {
  name = "KDG-UnauthenticatedUserRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.kdg.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "unauthenticated"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "kdg_unauth_policy" {
  name = "DenyAll"
  role = aws_iam_role.kdg_unauth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
    }]
  })
}

# ─── Cognito User Pool + User ─────────────────────────────────────────────────

resource "aws_cognito_user_pool" "kdg" {
  name = "KiensisDataGeneratorUserPool"

  password_policy {
    minimum_length    = 6
    require_uppercase = false
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "kdg" {
  name         = "KinesisDataGeneratorUserPoolClient"
  user_pool_id = aws_cognito_user_pool.kdg.id

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
}

resource "aws_cognito_user" "kdg" {
  user_pool_id = aws_cognito_user_pool.kdg.id
  username     = var.kdg_username

  password       = var.kdg_password
  message_action = "SUPPRESS"

  attributes = {
    email          = "${var.kdg_username}@example.com"
    email_verified = true
  }
}

resource "aws_cognito_identity_pool" "kdg" {
  identity_pool_name               = "KinesisDataGeneratorIdentityPool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.kdg.id
    provider_name           = aws_cognito_user_pool.kdg.endpoint
    server_side_token_check = false
  }
}

resource "aws_cognito_identity_pool_roles_attachment" "kdg" {
  identity_pool_id = aws_cognito_identity_pool.kdg.id

  roles = {
    authenticated   = aws_iam_role.kdg_auth.arn
    unauthenticated = aws_iam_role.kdg_unauth.arn
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "s3_bucket_name" {
  value = aws_s3_bucket.sdl.bucket
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}

output "firehose_role_arn" {
  value = aws_iam_role.firehose.arn
}

output "kdg_secret_arn" {
  value = aws_secretsmanager_secret.kdg.arn
}

output "kdg_url" {
  description = "Kinesis Data Generator URL"
  value       = "https://awslabs.github.io/amazon-kinesis-data-generator/web/producer.html?upid=${aws_cognito_user_pool.kdg.id}&cid=${aws_cognito_user_pool_client.kdg.id}&ipid=${aws_cognito_identity_pool.kdg.id}&r=${data.aws_region.current.name}"
}
