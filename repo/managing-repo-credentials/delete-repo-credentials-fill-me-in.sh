#!/bin/bash
#
# This script can be used to delete SentinelOne Repository authentication token/credentials used 
# to access the public/authenticated container registry (and rpm/deb repos).
#

# Customize these variables to from information from your SentinelOne Console
S1_MGMT="https://FILL-ME-IN.sentinelone.net"
S1_API_TOKEN="FILL-ME-IN"
S1_ACCOUNT_ID="FILL-ME-IN"
TOKEN_ID=$1

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

if [ -z ${1} ] || [ 1 -gt ${1} ]; then
    printf "\n${Red}ERROR:  Please enter a positive integer for TOKEN_ID.${Color_Off}\n"
    printf "\nUsage: ./$(basename "$0") TOKEN_ID${Color_Off}\n"
    exit 1
fi

function jq_check () {
    if ! [[ -x "$(which jq)" ]]; then
        printf "\n${Red}ERROR:  The jq utility cannot be found.  Please install it and ensure that it is accessible via PATH. ${Color_Off}\n"
        exit 1
    else
        printf "${Yellow}INFO:  jq is already installed.${Color_Off}\n"
    fi
}

function check_api_response () {
    if ! [ $RESPONSE = 'OK' ]; then
        printf "\n${Red}ERROR: \n $(echo $RESPONSE) ${Color_Off}\n"
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
printf "\n${Purple}Deleting token with id: $TOKEN_ID ${Color_Off}\n"
RESPONSE=$(curl -s -X DELETE --header "Content-Type: application/json" \
    --header "Authorization: ApiToken $S1_API_TOKEN" \
    "${S1_MGMT}/web/api/v2.1/agent-artifacts/token?scope_id=${S1_ACCOUNT_ID}&scope_level=account&token_id=${TOKEN_ID}")

# Check if command was successful
check_api_response

printf "\n${Green}Finished! ${Color_Off}\n"
exit 0