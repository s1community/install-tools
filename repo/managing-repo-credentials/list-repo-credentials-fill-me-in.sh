#!/bin/bash
#
# This script can be used to list SentinelOne Repository authentication token/credentials 
#

# Customize these variables to from information from your SentinelOne Console
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
        printf "\n${Red}ERROR: \n $(echo $RESPONSE | jq -r '.errors[]'). ${Color_Off}\n"
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

# Check if the API_TOKEN is in the right format
if  [[ ${#API_TOKEN} -le 79 ]] ; then
    printf "\n${Red}ERROR:  Invalid format for API_TOKEN: $API_TOKEN ${Color_Off}\n"
    echo "API Keys are generally 80 to 430 characters long and are alphanumeric."
    echo ""
    exit 1
fi

# Make sure that the jq utility is installed
jq_check

# Call the S1 Mgmt API to generate repo token/creds
RESPONSE=$(curl -s -X GET --header "Content-Type: application/json" \
    --header "Authorization: ApiToken $S1_API_TOKEN" \
    "${S1_MGMT}/web/api/v2.1/agent-artifacts/token?scope_id=${S1_ACCOUNT_ID}&scope_level=account")


# Check if command was successful
check_api_response

# Get the number of items in the response
NUM_ITEMS=$(echo $RESPONSE | jq ".data | length")
END_INDEX=$(($NUM_ITEMS - 1))
for i in $(seq 0 $END_INDEX)
do 
    # Gather output from the API response
    id=$(echo $RESPONSE | jq -r ".data[$i].id")
    token=$(echo $RESPONSE | jq -r ".data[$i].token")
    username=$(echo $RESPONSE | jq -r ".data[$i].username")
    scope_level=$(echo $RESPONSE | jq -r ".data[$i].scope_level")
    scope_id=$(echo $RESPONSE | jq -r ".data[$i].scope_id")
    created_at=$(echo $RESPONSE | jq -r ".data[$i].created_at")
    title=$(echo $RESPONSE | jq -r ".data[$i].title")
    description=$(echo $RESPONSE | jq -r ".data[$i].description")

    # Output the important variables
    printf "\n${Purple}################################################################################ ${Color_Off}\n"
    printf "${Purple}id:           $id ${Color_Off}\n"
    printf "${Purple}username:     $username ${Color_Off}\n"
    printf "${Purple}token:        $token ${Color_Off}\n"
    printf "${Purple}scope_level:  $scope_level ${Color_Off}\n"
    printf "${Purple}scope_id:     $scope_id ${Color_Off}\n"
    printf "${Purple}created_at:   $created_at ${Color_Off}\n"
    printf "${Purple}title:        $title ${Color_Off}\n"
    printf "${Purple}description:  $description ${Color_Off}\n\n"
done

# Save info to a file
REPO_INFO_FILE="list-repo-access-tokens-$(date +"%Y%m%d%H%M").json"
printf "\n${Yellow}Creating JSON File... ${Color_Off}\n"
echo $RESPONSE > $REPO_INFO_FILE

printf "\n${Green}Finished! ${Color_Off}\n"
exit 0
