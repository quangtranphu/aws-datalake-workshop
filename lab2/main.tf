terraform {
  required_version = "1.9.7"

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

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "sdl" {
  bucket = "sdl-immersion-day-${data.aws_caller_identity.current.account_id}"
}

data "aws_iam_role" "glue" {
  name = var.glue_role_name
}

resource "aws_glue_catalog_database" "sdl" {
  name        = var.glue_database_name
  description = "Glue catalog database for SDL raw data"
}

resource "aws_glue_crawler" "sdl_raw" {
  name          = var.crawler_name
  database_name = aws_glue_catalog_database.sdl.name
  role          = data.aws_iam_role.glue.arn

  # Crawl all sub-folders under raw/; on-demand schedule (no schedule block)
  s3_target {
    path = "s3://${data.aws_s3_bucket.sdl.bucket}/raw/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "glue_database_name" {
  value = aws_glue_catalog_database.sdl.name
}

output "glue_crawler_name" {
  value = aws_glue_crawler.sdl_raw.name
}

output "glue_crawler_arn" {
  value = aws_glue_crawler.sdl_raw.arn
}
