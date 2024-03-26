########### Create IAM User and Access Keys ###########

resource "aws_iam_user" "splunk_aws_addon_iam" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  name = "S1CloudFunnelSplunkUser"

  tags = {
    Purpose = "Splunk CloudFunnel User"
    URL = "https://splunkbase.splunk.com/app/1876"
  }
}

resource "aws_iam_access_key" "splunk_aws_addon_iam_access_key" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  user = aws_iam_user.splunk_aws_addon_iam[count.index].name
}

output "access_key_id" {
  value = try(aws_iam_access_key.splunk_aws_addon_iam_access_key[0].id, null)
  sensitive = true
}

output "secret_access_key" {
  value = try(aws_iam_access_key.splunk_aws_addon_iam_access_key[0].secret, null)
  sensitive = true
}

locals {
  splunk_aws_addon_iam_keys_csv = "access_key,secret_key\n${try(aws_iam_access_key.splunk_aws_addon_iam_access_key[0].id, "NULL")},${try(aws_iam_access_key.splunk_aws_addon_iam_access_key[0].secret, "NULL")}"
}

resource "local_file" "splunk_aws_addon_iam_keys" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0
  content  = local.splunk_aws_addon_iam_keys_csv
  filename = "splunk_aws_addon_iam-keys.csv"
}


########### Create IAM Policies ###########

# s3 bucket access

data "aws_iam_policy_document" "s3_bucket_actions" {
  statement {
    actions = [
      "s3:Get*",
      "s3:List*",
      "s3:Describe*",
      "s3:DeleteObject",
      "s3-object-lambda:Get*",
      "s3-object-lambda:List*"
    ]

    resources = [
      "${aws_s3_bucket.cloudfunnel_bucket.arn}/*",
    ]
  }
}

# sqs queue access

data "aws_iam_policy_document" "sqs_actions" {
  statement {
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ListQueues",
      "sqs:DeleteMessage",
      "sqs:ReceiveMessage",
      "sqs:ChangeMessageVisibility"
    ]

    resources = [
      "${aws_sqs_queue.cloudfunnel_queue.arn}",
    ]
  }
}

resource "aws_iam_policy" "s3_bucket_actions" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  name        = "S1S3CloudFunnelSplunkPolicy"
  policy      = data.aws_iam_policy_document.s3_bucket_actions.json
}

resource "aws_iam_policy" "sqs_actions" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  name        = "S1SQSCloudFunnelSplunkPolicy"
  policy      = data.aws_iam_policy_document.sqs_actions.json
}


########### Create IAM Role ###########

resource "aws_iam_role" "s1-cloudfunnel-splunk-role" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  name = "S1CloudFunnelSplunkRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          "AWS": "${aws_iam_user.splunk_aws_addon_iam[count.index].arn}"
        }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# attach role policies

resource "aws_iam_role_policy_attachment" "s3_bucket_actions_policy_attachment" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  policy_arn = "${aws_iam_policy.s3_bucket_actions[count.index].arn}"
  role       = aws_iam_role.s1-cloudfunnel-splunk-role[count.index].name
}

resource "aws_iam_role_policy_attachment" "sqs_bucket_actions_policy_attachment" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  policy_arn = "${aws_iam_policy.sqs_actions[count.index].arn}"
  role       = aws_iam_role.s1-cloudfunnel-splunk-role[count.index].name
}

resource "aws_iam_role_policy_attachment" "sqs_read_only_attachment" {
  count = var.sentinelone_create_splunk_iam ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"
  role       = aws_iam_role.s1-cloudfunnel-splunk-role[count.index].name
}