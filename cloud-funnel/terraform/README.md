# Sentinel One Deployment and Automation tools for Cloud Funnel 2.0

This Terraform module automates the steps in [How To Configure Your Amazon S3 Bucket](https://community.sentinelone.com/s/article/000006282).

It generates a resource name of `s1-random-pet-cloudfunnel` and then creates the following resources in AWS, defaulting to `us-east-1`.

* S3 Bucket
* S3 Bucket ACL with Access Control Policy for READ/WRITE by the Cloud Funnel Canonical ID
* 3-day object retention in Bucket
* SQS queue to monitor for Bucket write events

Once the resources are created, follow the steps in [How To Enable Cloud Funnel Streaming](https://community.sentinelone.com/s/article/000006285) to onboard.

## Prerequisites

* [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
* AWS credentials with permissions to create resources in your target region

## Execution

### Create Resources

```
terraform init
terraform apply
```

### Destroy Resources

```
terraform destroy
```

## Optional configuration

`provider.tf`

* `region` should be set to the target AWS Region

`terraform.tfvars`

* `sentinelone_bucket_prefix` can be updated to any desired string
