# managing-repo-credentials

These scripts provide examples of interacting with the SentinelOne Public Repository.

**Knowledge Base**
https://community.sentinelone.com/s/article/000008771

For each `fill-me-in` script, update the `FILL-ME-IN` placeholders to reflect your environment.

> [!CAUTION]
> Ensure that the `S1_API_TOKEN` is kept secret.
> Follow least-privilege best practices by creating a token with only *Generate*, *Revoke* and *List Token* permissions.


```
S1_MGMT="https://FILL-ME-IN.sentinelone.net"
S1_API_TOKEN="FILL-ME-IN"
S1_ACCOUNT_ID="FILL-ME-IN"
```

## create-repo-credentials-fill-me-in.sh

Usage: `./create-repo-credentials-fill-me-in.sh`

Each successful execution of this script will create new Public Repository credentials in the scope of the `S1_API_TOKEN`.

The credentials will be printed to the terminal and written to a datestamped file with the naming convention `s1-repo-info-*.json`

## delete-repo-credentials-fill-me-in.sh

Usage: `./delete-repo-credentials-fill-me-in.sh TOKEN_ID`

A successful execution of this script will delete the Public Repository credentials identified by the TOKEN_ID.

## list-repo-credentials-fill-me-in.sh

Each successful execution of this script will list existing Public Repository credentials in the scope of the `S1_API_TOKEN`.

The credentials will be printed to the terminal and written to a datestamped file with the naming convention `list-repo-access-tokens-*.json`

## docker-login-repo-credentials.sh

Usage: `./docker-login-repo-credentials.sh`

Each successful execution of this script will log into the local Docker cli using the `username` and `token` from the most recent `s1-repo-info-*.json` file.

The equivalent command line is:

```
docker login containers.sentinelone.net -u username -p token 2>/dev/null
```