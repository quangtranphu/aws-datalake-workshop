variable "aws_region" {
  description = "AWS region"
  default     = "eu-central-1"
}

variable "aws_account_number" {
  description = "AWS account number, used to build the S3 bucket name sdl-immersion-day-{account}"
  type        = string
}

variable "firehose_role_name" {
  description = "Name of the existing IAM role to attach to the Firehose delivery stream"
  type        = string
  default     = "SDL-FirehoseRole"
}

variable "delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream"
  type        = string
  default     = "sdl-firehose-stream"
}