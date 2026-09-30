data "aws_caller_identity" "current" {}

locals {
  account_id          = data.aws_caller_identity.current.account_id
  region              = var.aws_region
  embedding_model_arn = "arn:aws:bedrock:${local.region}::foundation-model/${var.embedding_model_id}"
  gdelt_bucket_arn    = "arn:aws:s3:::${var.gdelt_bucket}"
}

# ---------------------------------------------------------------------------
# IAM — Bedrock Knowledge Base role (pre-created by 00-setup CloudFormation)
# ---------------------------------------------------------------------------

data "aws_iam_role" "kb_role" {
  name = "${var.project_name}-kb-role"
}

# ---------------------------------------------------------------------------
# S3 Vectors — vector bucket and index (AWS-managed, no AOSS needed)
# ---------------------------------------------------------------------------

resource "aws_s3vectors_vector_bucket" "gdelt" {
  vector_bucket_name = "${var.project_name}-vectors"
}

resource "aws_s3vectors_index" "gdelt" {
  vector_bucket_name = aws_s3vectors_vector_bucket.gdelt.vector_bucket_name
  index_name         = "gdelt-index"
  data_type          = "float32"
  dimension          = var.vector_dimensions
  distance_metric    = "cosine"
}

# ---------------------------------------------------------------------------
# Bedrock Knowledge Base — backed by S3 Vectors
# ---------------------------------------------------------------------------

resource "aws_bedrockagent_knowledge_base" "gdelt" {
  name        = "${var.project_name}-kb"
  description = "Knowledge base over GDELT event data at s3://${var.gdelt_bucket}/${var.gdelt_prefix}"
  role_arn    = data.aws_iam_role.kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = local.embedding_model_arn
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.gdelt.index_arn
    }
  }

  depends_on = [aws_s3vectors_index.gdelt]
}

# ---------------------------------------------------------------------------
# S3 data source — points at the GDELT prefix
# ---------------------------------------------------------------------------

resource "aws_bedrockagent_data_source" "gdelt_s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.gdelt.id
  name              = "gdelt-s3-source"
  description       = "GDELT dataset from s3://${var.gdelt_bucket}/${var.gdelt_prefix}"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = local.gdelt_bucket_arn
      inclusion_prefixes = [var.gdelt_prefix]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 150
        overlap_percentage = 10
      }
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — AgentCore runtime role (pre-created by 00-setup CloudFormation)
# ---------------------------------------------------------------------------

data "aws_iam_role" "agentcore_role" {
  name = "${var.project_name}-agentcore-role"
}
