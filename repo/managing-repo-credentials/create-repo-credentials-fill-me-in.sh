#!/bin/bash
#
# This script can be used to generate SentinelOne Repository authentication token/credenetials for 
# accessing SentinelOne's public/authenticated container registry (and rpm/deb repos).
# Please see the associated Knowledge Base article here:
# https://community.sentinelone.com/s/article/000008771
#

# Customize these variables from information obtained via your SentinelOne Console
S1_MGMT="https://FILL-ME-IN.sentinelone.net"
S1_API_TOKEN="FILL-ME-IN"
S1_ACCOUNT_ID="FILL-ME-IN"


# Variables to colorize output
Color_Off='\033[0m'       # Text Resets
# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

function jq_check () {
    if ! [[ -x "$(which jq)" ]]; then
        printf "\n${Red}ERROR:  The jq utility cannot be found.  Please install it and ensure that it is accessible via PATH. ${Color_Off}\n"
        exit 1
    else
        printf "${Yellow}INFO:  jq is already installed.${Color_Off}\n"
    fi
}

function check_api_response () {
    if [[ $(echo $RESPONSE | jq 'has("errors")') == 'true' ]]; then
        printf "\n${Red}ERROR: \n $(echo $Response | jq -r ".errors"). ${Color_Off}\n"
        echo ""
        exit 1
    fi
}

# Check if the S1_ACCOUNT_ID is in the right format/length
if ! [[ $S1_ACCOUNT_ID =~ ^[0-9]{18,19}$ ]]; then
    printf "\n${Red}ERROR:  Invalid format for S1_ACCOUNT_ID: $S1_ACCOUNT_ID ${Color_Off}\n"
    echo "SentinelOne Account IDs are generally 18-19 numeric characters in length."
    echo ""
    exit 1
fi

# Check if the API_KEY is in the right format
if ! [[ ${#S1_API_TOKEN} -eq 80 ]]; then
    printf "\n${Red}ERROR:  Invalid format for S1_API_TOKEN: $S1_API_TOKEN ${Color_Off}\n"
    echo "API Tokens are generally 80 characters long and are alphanumeric."
    echo ""
    exit 1
fi

# Make sure that the jq utility is installed
jq_check

# Call the S1 Mgmt API to generate repo token/creds
RESPONSE=$(curl -s -X POST "${S1_MGMT}/web/api/v2.1/agent-artifacts/token" \
    --header "Content-Type: application/json" \
    --header "Authorization: ApiToken ${S1_API_TOKEN}" \
    --data @- << EOF
{
    "title": "title_goes_here", 
    "description": "description_goes_here", 
    "scope_level": "account", 
    "scope_id": "${S1_ACCOUNT_ID}"
}
EOF
)

# Check if command was successful
check_api_response

# Gather output from the API response
id=$(echo $RESPONSE | jq -r ".id")
token=$(echo $RESPONSE | jq -r ".token")
username=$(echo $RESPONSE | jq -r ".username")
scope_level=$(echo $RESPONSE | jq -r ".scope_level")
scope_id=$(echo $RESPONSE | jq -r ".scope_id")
created_at=$(echo $RESPONSE | jq -r ".created_at")
title=$(echo $RESPONSE | jq -r ".title")
description=$(echo $RESPONSE | jq -r ".description")

# Output the important variables
printf "\n${Purple}username: $username ${Color_Off}\n"
printf "\n${Purple}token: $token ${Color_Off}\n"


# Save info to a file
REPO_INFO_FILE="s1-repo-info-$(date +"%Y%m%d%H%M").json"
printf "\n${Yellow}Creating JSON File... ${Color_Off}\n"
echo $RESPONSE > $REPO_INFO_FILE

printf "\n${Green}Finished! ${Color_Off}\n"