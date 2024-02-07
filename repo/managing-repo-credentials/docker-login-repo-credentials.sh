#!/bin/bash
#
# This script can be used to log into the SentinelOne Repository 
# using Docker and the most recent s1-repo-info json file
#

# Script variables
S1_REPO="containers.sentinelone.net"

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

function docker_check () {
    if ! [[ -x "$(which docker)" ]]; then
        printf "\n${Red}ERROR:  The docker utility cannot be found.  Please install it and ensure that it is accessible via PATH. ${Color_Off}\n"
        exit 1
    else
        printf "${Yellow}INFO:  docker is already installed.${Color_Off}\n"
    fi
}

# Make sure that the jq utility is installed
jq_check

# Make sure that the docker cli is installed
docker_check

# Find the most recent s1-repo-info json file
LATEST_REPO_JSON=$(ls -t s1-repo-info*json | head -1)
if [ -z ${LATEST_REPO_JSON} ] || [ ! -f ${LATEST_REPO_JSON} ]; then 
    printf "\n${Red}ERROR:  The most current s1-repo-info json file cannot be found.  Please ensure you have configured and run create-repo-credentials-fill-me-in.sh. ${Color_Off}\n"
    exit 1
else
    printf "${Yellow}INFO:  Attempting to log in with credentials in ${LATEST_REPO_JSON}.${Color_Off}\n"
fi

S1_REPO_USER=$(cat ${LATEST_REPO_JSON} | jq -r '.username')
S1_REPO_PASS=$(cat ${LATEST_REPO_JSON} | jq -r '.token')

# ignore WARNING from docker
# the password is stored in a flat file and passing it directly to the login 
# command is no less secure
docker login ${S1_REPO} -u ${S1_REPO_USER} -p ${S1_REPO_PASS} 2>/dev/null
if [ $? -eq 0 ]; then
    printf "\n${Green}Succesfully logged into docker cli! ${Color_Off}\n"
else
    printf "\n${Red}ERROR:  Could not log into docker cli. ${Color_Off}\n"
    exit 1
fi

printf "\n${Green}Finished! ${Color_Off}\n"
exit 0