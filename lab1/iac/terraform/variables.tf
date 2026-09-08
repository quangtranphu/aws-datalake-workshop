variable "aws_region" {
  description = "AWS region"
  default     = "eu-central-1"
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