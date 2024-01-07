# s1-k8s-agent-install-repo.sh

A helper script to automate the installation, association to a site and activation of SentinelOne Kubernetes from the SentinelOne [Artifact Repository](https://community.sentinelone.com/s/article/000008771).

## Detailed Description

## Usage

```
sudo ./s1-k8s-agent-install-repo.sh S1_REPOSITORY_USERNAME S1_REPOSITORY_PASSWORD S1_SITE_TOKEN S1_AGENT_TAG S1_AGENT_LOG_LEVEL K8S_TYPE
```
| Argument | Explanation | Required |
| -------- | ----------- | -------- |
| S1_REPOSITORY_USERNAME | Your private registry username | Yes |
| S1_REPOSITORY_PASSWORD | Your private registry password | Yes |
| S1_SITE_TOKEN | Your SentinelOne Site Token | Yes |
| S1_AGENT_TAG | The version/tag of the K8s agent. ie: 23.4.1-ea | Yes |
| S1_AGENT_LOG_LEVEL | Your private registry password. ie: info (default), debug | No |
| K8S_TYPE | The target K8s type.  ie: k8s (default), openshift, fargate | No |