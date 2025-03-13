#!/bin/bash
##############################################################################################################
# Description: Bash script to assist in listing the available S1 CWS Container agent and helper images (GA and EA tags) from our public repository
# 
# Usage: sudo ./s1-k8s-list-container-images-tags.sh S1_REPOSITORY_USERNAME S1_REPOSITORY_PASSWORD
# 
# Version:  2025.03.13
#
# Reference:  https://community.sentinelone.com/s/article/000008772
#
# NOTE: This script will install the jq and curl utilities on Ubuntu / Debian systems if not already installed.
#
# NOTE: Please be aware that there is a 100 pulls/hour rate limit for the SentinelOne repository!!
##############################################################################################################

# Color control constants
Color_Off='\033[0m'       # Text Resets
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White


################################################################################
# Gather Inputs
################################################################################
# How to Install the Agent from a Public Repository: https://community.sentinelone.com/s/article/000008771
# S1_REPOSITORY_USERNAME=""
# S1_REPOSITORY_PASSWORD=""

# The following variables SHOULD NOT BE ALTERED
REPO_BASE="containers.sentinelone.net"

# Check if all 2 arguments were passed to the script
if [ $# -eq 2 ]; then
    printf "\n${Yellow}INFO:  Found $# arguments that were passed to the script. \n\n${Color_Off}"
    S1_REPOSITORY_USERNAME=$1
    S1_REPOSITORY_PASSWORD=$2
fi

# Check if arguments have been passed at all.
if [ $# -eq 0 ]; then
    printf "\n${Yellow}INFO: No input arguments were passed to the script. \n\n${Color_Off}"
fi

# If the 2 needed variables have not been passed via cmdline arguments or
# read from exported variables of the parent shell, we'll prompt the user for them.
if [ -z $S1_REPOSITORY_USERNAME ];then
    echo ""
    read -p "Please enter your SentinelOne Repo Username: " S1_REPOSITORY_USERNAME
fi

if [ -z $S1_REPOSITORY_PASSWORD ];then
    echo ""
    read -p "Please enter your SentinelOne Repo Password: " S1_REPOSITORY_PASSWORD
fi

# Ensure curl is installed before sending an HTTP GET request to retrieve the list of tags from the container image repository
if ! (which curl &> /dev/null); then
    printf "\n${Yellow}INFO:  Installing curl utility in order to retrieve the list of tags... ${Color_Off}\n"
    apt-get update
    apt-get install -y curl
    if [ $? -ne 0 ]; then
        printf "\n${Red}ERROR: Unable to install required dependency curl.${Color_Off}\n"
        exit 1
    fi
fi

# Ensure jq is installed before parsing JSON data
if ! (which jq &> /dev/null); then
    printf "\n${Yellow}INFO: Installing jq utility in order to parse JSON data that is returned from the curl command... ${Color_Off}\n"
    apt-get update
    apt-get install -y jq
    if [ $? -ne 0 ]; then
        printf "\n${Red}ERROR: Unable to install required dependency jq.${Color_Off}\n"
        exit 1
    fi
fi

# Function to fetch and print tags
fetch_and_print_tags() {
    local image_path=$1
    local tag_type=$2

    # Fetch the list of multi-arch tags
    TAGS=$(curl -u $S1_REPOSITORY_USERNAME:$S1_REPOSITORY_PASSWORD -s "https://$REPO_BASE/v2/$image_path/tags/list" | jq -r '.tags[]' | grep "$tag_type$" | grep -Ev "x86|aarch|amd" | sort -Vr)

    echo "Available $tag_type tags for ${image_path}:"
    for tag in ${TAGS}; do
        echo $tag
    done
}

# Image paths
IMAGE_PATHS=("cws-agent/s1agent" "cws-agent/s1helper")

# Loop through image paths and fetch both GA and EA tags
for image_path in "${IMAGE_PATHS[@]}"; do
    fetch_and_print_tags $image_path "ga"
    fetch_and_print_tags $image_path "ea"
done

exit 0