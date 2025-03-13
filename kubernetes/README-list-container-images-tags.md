
# s1-k8s-public-registry-list-container-images-tags.sh
A helper script to list the available SentinelOne CWS Container agent and helper images (GA and EA tags) from the SentinelOne [Artifact Repository](https://community.sentinelone.com/s/article/000008771).

## Detailed Description

## Usage

```
curl -sLO https://raw.githubusercontent.com/s1community/install-tools/refs/heads/main/kubernetes/s1-k8s-list-container-images-tags.sh
chmod +x s1-k8s-list-container-images-tags.sh
./s1-k8s-list-container-images-tags.sh S1_REPOSITORY_USERNAME S1_REPOSITORY_PASSWORD
```
| Argument | Explanation | Required |
| -------- | ----------- | -------- |
| S1_REPOSITORY_USERNAME | Your private registry username | Yes |
| S1_REPOSITORY_PASSWORD | Your private registry password | Yes |
