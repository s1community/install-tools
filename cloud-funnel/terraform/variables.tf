variable "sentinelone_aws_id" {
  description = "AWS Canonical User ID for Cloud Funnel cross-account access"
  type        = string
}

variable "sentinelone_bucket_prefix" {
  description = "String prefix to add to Cloud Funnel S3 bucket"
  type        = string
}
variable "sentinelone_create_splunk_iam" {
  description = "boolean to determine whether to create IAM resources for Splunk Add-on"
  type        = bool
}
