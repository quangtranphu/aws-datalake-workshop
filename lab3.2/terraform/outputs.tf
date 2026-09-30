output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID — set as KNOWLEDGE_BASE_ID env var in the agent runtime"
  value       = aws_bedrockagent_knowledge_base.gdelt.id
}

output "knowledge_base_arn" {
  description = "Bedrock Knowledge Base ARN"
  value       = aws_bedrockagent_knowledge_base.gdelt.arn
}

output "data_source_id" {
  description = "Bedrock Knowledge Base data source ID"
  value       = aws_bedrockagent_data_source.gdelt_s3.data_source_id
}

output "vector_bucket_name" {
  description = "S3 Vectors bucket name backing the knowledge base"
  value       = aws_s3vectors_vector_bucket.gdelt.vector_bucket_name
}

output "vector_bucket_arn" {
  description = "S3 Vectors bucket ARN backing the knowledge base"
  value       = aws_s3vectors_vector_bucket.gdelt.vector_bucket_arn
}

output "kb_iam_role_arn" {
  description = "IAM role ARN assumed by the Bedrock Knowledge Base"
  value       = data.aws_iam_role.kb_role.arn
}

output "agentcore_iam_role_arn" {
  description = "IAM role ARN to pass to AgentCore runtime for the GDELT agent"
  value       = data.aws_iam_role.agentcore_role.arn
}

output "sync_command" {
  description = "AWS CLI command to trigger a knowledge base sync after new data lands in S3"
  value = join(" ", [
    "aws bedrock-agent start-ingestion-job",
    "--knowledge-base-id", aws_bedrockagent_knowledge_base.gdelt.id,
    "--data-source-id", aws_bedrockagent_data_source.gdelt_s3.data_source_id,
    "--region", var.aws_region,
  ])
}
