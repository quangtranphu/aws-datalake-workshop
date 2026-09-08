variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "glue_role_name" {
  description = "Name of the existing IAM role for Glue"
  type        = string
  default     = "SDL-GlueRole"
}

variable "glue_database_name" {
  description = "Name of the Glue catalog database to create"
  type        = string
  default     = "sdl-demo-data"
}

variable "crawler_name" {
  description = "Name of the Glue crawler"
  type        = string
  default     = "sdl-demo-crawler"
}
