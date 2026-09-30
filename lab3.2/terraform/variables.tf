variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name used as a prefix for resource names"
  type        = string
  default     = "gdelt-agent"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "gdelt_bucket" {
  description = "S3 bucket containing the GDELT dataset"
  type        = string
  default     = "sdl-immersion-day-220334428465"
}

variable "gdelt_prefix" {
  description = "S3 prefix (folder) for the GDELT data within the bucket"
  type        = string
  default     = "gdelt/"
}

variable "embedding_model_id" {
  description = "Bedrock foundation model ID used for document embeddings"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "vector_dimensions" {
  description = "Embedding vector dimensions — must match the chosen embedding model"
  type        = number
  default     = 1024
}
