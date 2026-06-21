# s1-k8s-agent-install-repo.sh

A helper script to automate the installation, site association, and activation of the SentinelOne CWS Container agent from the SentinelOne [container registry](https://community.sentinelone.com/s/article/000011517).

## Usage

Inputs can be supplied via an **`s1.config` file (recommended)**, command-line arguments, or interactive prompts. When more than one source provides the same value, it resolves in this order (highest precedence first):

1. Positional command-line arguments (only applied when 4 or more are passed)
2. Values in an `s1.config` file in the current directory
3. Exported environment variables inherited from the parent shell
4. Interactive prompts for any required value still missing

### Option 1 — `s1.config` file (recommended)

Using a config file keeps your registry credentials and site token out of your shell history and out of the process list (`ps`).

```
# Download the script and the example config
curl -sLO https://raw.githubusercontent.com/s1community/install-tools/refs/heads/main/kubernetes/s1-k8s-agent-install-repo.sh
curl -sLO https://raw.githubusercontent.com/s1community/install-tools/refs/heads/main/kubernetes/s1.config.example
chmod +x s1-k8s-agent-install-repo.sh

# Create your config from the template, then fill in your values
cp s1.config.example s1.config
$EDITOR s1.config

# Run from the same directory; s1.config is sourced automatically
sudo ./s1-k8s-agent-install-repo.sh
```

### Option 2 — command-line arguments

```
curl -sLO https://raw.githubusercontent.com/s1community/install-tools/refs/heads/main/kubernetes/s1-k8s-agent-install-repo.sh
chmod +x s1-k8s-agent-install-repo.sh
./s1-k8s-agent-install-repo.sh [S1_REPOSITORY_USERNAME] [S1_REPOSITORY_PASSWORD] [S1_SITE_TOKEN] [S1_AGENT_TAG] [S1_AGENT_LOG_LEVEL] [K8S_TYPE] [S1_ADMISSION_CONTROLLER]
```

> **Warning:** Passing your registry credentials and site token as command-line arguments records them in your shell history (e.g. `~/.bash_history`) and exposes them to other local users via the process list (`ps`). Prefer an `s1.config` file (Option 1), or run with no arguments to be prompted interactively (prompt input is not echoed or stored).

### Arguments

| # | Argument | Description / valid values | Required | Default |
| - | -------- | -------------------------- | -------- | ------- |
| 1 | S1_REPOSITORY_USERNAME | SentinelOne container registry username | Yes | - |
| 2 | S1_REPOSITORY_PASSWORD | SentinelOne container registry password | Yes | - |
| 3 | S1_SITE_TOKEN | Your SentinelOne Site or Group token | Yes | - |
| 4 | S1_AGENT_TAG | Agent version/tag, format `X.Y.Z-(ga\|ea)`, e.g. `26.1.1-ga` | Yes | - |
| 5 | S1_AGENT_LOG_LEVEL | `trace` \| `debug` \| `info` \| `warning` \| `error` \| `fatal` | No | `info` |
| 6 | K8S_TYPE | `k8s` \| `openshift` \| `autopilot` \| `fargate` \| `eksauto` | No | `k8s` |
| 7 | S1_ADMISSION_CONTROLLER | `true` \| `false` — deploy the validating admission controller webhook | No | `true` |

> **Note:** Setting `S1_ADMISSION_CONTROLLER=true` only deploys the validating admission controller webhook. To actually monitor and/or enforce, you must also enable an [Admission Controller Policy](https://community.sentinelone.com/s/article/000011916) in the SentinelOne management console.

## References

| Topic | KB Article |
| ----- | ---------- |
| Create Repo Username/Password (see "Manual deployment for Container Agent") | [000011517](https://community.sentinelone.com/s/article/000011517) |
| Retrieve a Site Token | [000004904](https://community.sentinelone.com/s/article/000004904) |
| Find the latest Agent version | [000004966](https://community.sentinelone.com/s/article/000004966) |
| Supported Kubernetes types & resource sizing | [000008829](https://community.sentinelone.com/s/article/000008829) |
| All Helm chart options | [000008816](https://community.sentinelone.com/s/article/000008816) |
| Configuring Admission Controller policies | [000011916](https://community.sentinelone.com/s/article/000011916) |
| Deploying to GKE Autopilot | [000011984](https://community.sentinelone.com/s/article/000011984) |
| Deploying on Kubernetes with EKS Fargate | [000012505](https://community.sentinelone.com/s/article/000012505) |

> **Note:** There is a 100 pulls/hour rate limit for the SentinelOne repository.
