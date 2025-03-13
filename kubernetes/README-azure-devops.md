# azure-devops-pipeline-example.yml

A sample pipeline for use in [Azure DevOps](https://azure.microsoft.com/en-us/products/devops/pipelines) to deploy the SentinelOne CWS Container agent to an existing EKS cluster.

## Prerequisites

- Azure AKS Cluster
- `azure-devops-pipeline-example.yml`
- SentinelOne Container Registry user and token
  - https://community.sentinelone.com/s/article/000008771
- SentinelOne Site or Group Token
  - https://community.sentinelone.com/s/article/000004904


## Usage

Import the pipeline to your Azure DevOps Project

Create three pipeline variables to store the following keys and their corresponding values:

- S1_PULL_SECRET_USERNAME
- S1_PULL_SECRET_TOKEN
- S1_SITE_TOKEN

Update `azureSubscription`, `resourceGroup`, and `aksClusterName` to reflect your environment.

Run the pipeline and review pipeline output for errors.
