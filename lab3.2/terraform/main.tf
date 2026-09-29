data "aws_caller_identity" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  region         = var.aws_region
  collection_name = "${var.project_name}-vectors"
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
# OpenSearch Serverless — encryption, network, and access policies
# ---------------------------------------------------------------------------

resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${var.project_name}-enc"
  type        = "encryption"
  description = "AWS-managed encryption for ${local.collection_name}"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.collection_name}"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${var.project_name}-net"
  type        = "network"
  description = "Public access for ${local.collection_name}"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${local.collection_name}"]
      },
    ]
    AllowFromPublic = true
  }])
}

resource "aws_opensearchserverless_access_policy" "access" {
  name        = "${var.project_name}-access"
  type        = "data"
  description = "Grants KB role and admins full index access"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "index"
        Resource     = ["index/${local.collection_name}/*"]
        Permission   = ["aoss:*"]
      },
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
        Permission   = ["aoss:*"]
      },
    ]
    Principal = concat(
      [data.aws_iam_role.kb_role.arn],
      var.additional_admin_arns,
    )
  }])
}

# ---------------------------------------------------------------------------
# OpenSearch Serverless collection
# ---------------------------------------------------------------------------

resource "aws_opensearchserverless_collection" "gdelt" {
  name        = local.collection_name
  type        = "VECTORSEARCH"
  description = "Vector store for GDELT events knowledge base"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.access,
  ]
}

# Allow the collection to become ACTIVE before creating the knowledge base.
resource "time_sleep" "wait_for_collection" {
  create_duration = "90s"
  depends_on      = [aws_opensearchserverless_collection.gdelt]
}

# ---------------------------------------------------------------------------
# Bedrock Knowledge Base
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
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.gdelt.arn
      vector_index_name = var.aoss_index_name
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  depends_on = [time_sleep.wait_for_collection]
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
        max_tokens         = 512
        overlap_percentage = 20
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
