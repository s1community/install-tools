# container-pull-push

##  s1-pull-private-push.sh

This script will download container images from the SentinelOne Repository and push them 
to your private registry.

https://community.sentinelone.com/s/article/000008771


### Prerequisites

1. Credentials for SentinelOne Repository.  Please create credentials in your Management Console or use the scripts in [managing-repo-credentials](../managing-repo-credentials).
2. [Docker cli](https://docs.docker.com/engine/install/)
3. Private registry and credentials, including but not limited to:
- Amazon Elastic Container Registry (ECR)
- Azure Container Registry (ACR)
- Google Artifact Registry
- Red Hat Quay

### Setup

1. Log into your private registry with `docker login`

2. Configure `s1.config` or identify values associated with each variable to pass on the command line.

```
cp s1.config.example s1.config

[update all values in s1.config to reflect your private registry configuration]
```

### Usage

- To use `s1.config` or manually provide each required parameter:

```
./s1-pull-private-push.sh
```


- To pass all variables to the script at launch time:

```
./s1-pull-private-push.sh S1_REPOSITORY_USERNAME S1_REPOSITORY_PASSWORD S1_AGENT_TAG \
  PRIVATE_REPO_BASE PRIVATE_REPO_AGENT_NAME PRIVATE_REPO_HELPER_NAME
```

### Troubleshooting

The script will exit before completion if any step fails.  

Output from each `docker` command will indicate the cause of the error.
