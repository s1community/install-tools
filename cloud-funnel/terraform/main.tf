########### Setup ###########

resource "random_pet" "name" {
    prefix = var.sentinelone_bucket_prefix
}

resource "random_string" "suffix" {
    length  = 8
    special = false
}

data "aws_canonical_user_id" "current" {}
data "aws_caller_identity" "current" {}


########### S3 Bucket ###########

resource "aws_s3_bucket" "cloudfunnel_bucket" {
    bucket          = "${random_pet.name.id}-cloudfunnel"
    force_destroy   = true
}

resource "aws_s3_bucket_ownership_controls" "cloudfunnel_bucket" {
  bucket = aws_s3_bucket.cloudfunnel_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "cloudfunnel_bucket_acl" {
    bucket = aws_s3_bucket.cloudfunnel_bucket.id
    acl    = "private"
    depends_on = [aws_s3_bucket_ownership_controls.cloudfunnel_bucket]
}

resource "aws_s3_bucket_acl" "cloudfunnel_bucket_grant" {

    bucket = aws_s3_bucket.cloudfunnel_bucket.id
    depends_on = [aws_s3_bucket_acl.cloudfunnel_bucket_acl]

    access_control_policy {
        grant {
            grantee {
                id   = var.sentinelone_aws_id
                type = "CanonicalUser"
            }
            permission = "READ"
        }

        grant {
            grantee {
                id   = var.sentinelone_aws_id
                type = "CanonicalUser"
            }
            permission = "WRITE"
        }

        grant {
            grantee {
                id   = data.aws_canonical_user_id.current.id
                type = "CanonicalUser"
            }
            permission = "READ"
        }

        grant {
            grantee {
                id   = data.aws_canonical_user_id.current.id
                type = "CanonicalUser"
            }
            permission = "WRITE"
        }

        grant {
            grantee {
                id   = data.aws_canonical_user_id.current.id
                type = "CanonicalUser"
            }
            permission = "READ_ACP"
        }

        grant {
            grantee {
                id   = data.aws_canonical_user_id.current.id
                type = "CanonicalUser"
            }
            permission = "WRITE_ACP"
        }

        owner {
            id = data.aws_canonical_user_id.current.id
        }
    }
}

resource "aws_s3_bucket_public_access_block" "cloudfunnel_bucket_access_block" {
    bucket = aws_s3_bucket.cloudfunnel_bucket.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfunnel_bucket_sse_config" {
    bucket = aws_s3_bucket.cloudfunnel_bucket.bucket

    rule {
        bucket_key_enabled  = true
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudfunnel_bucket_3days" {
    bucket = aws_s3_bucket.cloudfunnel_bucket.id
    rule {
        status = "Enabled"
        id     = "expire_all_files"
        expiration {
            days = 3
        }
    }
}

resource "aws_s3_bucket_notification" "cloudfunnel_bucket_notification" {
    bucket      = aws_s3_bucket.cloudfunnel_bucket.id
    depends_on  = [ aws_sqs_queue_policy.cloudfunnel_queue ]

    queue {
        queue_arn     = aws_sqs_queue.cloudfunnel_queue.arn
        events        = ["s3:ObjectCreated:*"]
        filter_suffix = ".gz"

    }
}


########### SQS Queue ###########

data "aws_iam_policy_document" "cloudfunnel_queue" {
  statement {
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["SQS:SendMessage"]
    resources = ["${aws_sqs_queue.cloudfunnel_queue.arn}"]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [ aws_s3_bucket.cloudfunnel_bucket.arn ]
    }
  }
}

resource "aws_sqs_queue" "cloudfunnel_queue" {
    name                        = "${random_pet.name.id}-cloudfunnel"
    sqs_managed_sse_enabled     = true
    message_retention_seconds   = 86400
    visibility_timeout_seconds  = 300

    redrive_policy = jsonencode(
    {
        deadLetterTargetArn = "${aws_sqs_queue.cloudfunnel_dlq.arn}"
        maxReceiveCount     = 10
    }
    )
}

resource "aws_sqs_queue_policy" "cloudfunnel_queue" {
    queue_url = aws_sqs_queue.cloudfunnel_queue.id
    policy    = data.aws_iam_policy_document.cloudfunnel_queue.json
}

resource "aws_sqs_queue" "cloudfunnel_dlq" {
    name                        = "${random_pet.name.id}-cloudfunnel-DLQ"
    sqs_managed_sse_enabled     = true
    message_retention_seconds   = 14400
}
