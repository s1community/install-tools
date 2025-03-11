#!/usr/bin/env bash
##############################################################################################################
# Description:  Bash script to aid with automating S1 Linux Agent install with AWS Systems Manager
#
# Pre-requisites: EC2 instances must have IAM permissions to access Systems Manager (ie: AmazonEC2RoleforSSM)
#
# Version:  1.0
##############################################################################################################


# NOTE:  This version will install the latest EA or GA version of the SentinelOne Linux agent
# NOTE:  This script will install the curl and jq utilities if not already installed.

# References:
# - https://docs.aws.amazon.com/systems-manager/latest/userguide/integration-s3.html

# CUSTOMIZE THE VALUE OF AWS_REGION TO FIT YOUR SSM ENVIRONMENT
AWS_REGION=us-east-1

# Retrieve values from Systems Manager Parameter Store
S1_MGMT_URL=$(aws ssm get-parameters --names S1_MGMT_URL --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)
API_KEY=$(aws ssm get-parameters --names S1_API_KEY --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)
SITE_TOKEN=$(aws ssm get-parameters --names S1_SITE_TOKEN --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)
S1_VERSION_STATUS=$(aws ssm get-parameters --names S1_VERSION_STATUS --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)   # "EA" or "GA"

API_ENDPOINT='/web/api/v2.1/update/agent/packages'
FILE_EXTENSION=''
PACKAGE_MANAGER=''
AGENT_INSTALL_SYNTAX=''
AGENT_FILE_NAME=''
AGENT_DOWNLOAD_LINK=''

Color_Off='\033[0m'       # Text Resets
# Regular Colors
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow

# Check if running as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    printf "\n%sERROR:  This script must be run as root.  Please retry with 'sudo'.%s\n" "${Red}" "${Color_Off}"
    exit 1
fi

# Check if curl is installed.
function curl_check () {
    if ! command -v curl &> /dev/null; then
        printf "\n%sINFO:  Installing curl utility in order to interact with S1 API... %s\n" "${Yellow}" "${Color_Off}"
        if [[ $1 = 'apt' ]]; then
            sudo apt-get update && sudo apt-get install -y curl
        elif [[ $1 = 'yum' ]]; then
            sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            sudo yum install -y curl
        elif [[ $1 = 'zypper' ]]; then
            sudo zypper install -y curl
        elif [[ $1 = 'dnf' ]]; then
            sudo dnf install -y curl
        else
            printf "\n%sERROR:  Unsupported file extension.%s\n" "${Red}" "${Color_Off}"
        fi
    else
        printf "%sINFO:  curl is already installed.%s\n" "${Yellow}" "${Color_Off}"
    fi
}

# Check if the SITE_TOKEN is in the right format
if ! [[ ${#SITE_TOKEN} -gt 90 ]]; then
    printf "\n%sERROR:  Invalid format for SITE_TOKEN: %s %s\n" "${Red}" "$SITE_TOKEN" "${Color_Off}"
    echo "Site Tokens are generally more than 90 characters long and are ASCII encoded."
    echo ""
    exit 1
fi

# Check if the API_KEY is in the right format
if ! [[ ${#API_KEY} -gt 79 ]]; then
    printf "\n%sERROR:  Invalid format for API_KEY: %s %s\n" "${Red}" "$API_KEY" "${Color_Off}"
    echo "API Keys are generally 80 to 430 characters long and are alphanumeric."
    echo ""
    exit 1
fi

# Check if the VERSION_STATUS is in the right format
VERSION_STATUS=$(echo "$S1_VERSION_STATUS" | awk '{print tolower($0)}')
if [[ ${VERSION_STATUS} != *"ga"* && "$VERSION_STATUS" != *"ea"* ]]; then
    printf "\n%sERROR:  Invalid format for VERSION_STATUS: %s %s\n" "${Red}" "${VERSION_STATUS}" "${Color_Off}"
    echo "The value of VERSION_STATUS must contain either 'ea' or 'ga'"
    echo ""
    exit 1
fi

# Check if jq is installed
function jq_check () {
    if ! command -v jq &>/dev/null; then
        printf "\n%sINFO:  Installing jq utility in order to parse JSON responses from API... %s\n" "${Yellow}" "${Color_Off}"
        if [[ $1 = 'apt' ]]; then
            sudo apt-get update && sudo apt-get install -y jq
        elif [[ $1 = 'yum' ]]; then
            sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            sudo yum install -y jq
        elif [[ $1 = 'zypper' ]]; then
            sudo zypper install -y jq
        elif [[ $1 = 'dnf' ]]; then
            sudo dnf install -y jq
        else
            printf "\n%sERROR:  Unsupported file extension: %s %s\n" "${Red}" "$1" "${Color_Off}"
        fi
    else
        printf "%sINFO:  jq is already installed.%s\n" "${Yellow}" "${Color_Off}"
    fi
}

function check_api_response () {
    if [[ $(jq 'has("errors")' < response.txt) == 'true' ]]; then
        printf "\n%sERROR:  Could not authenticate using the existing mgmt server and api key. %s\n" "${Red}" "${Color_Off}"
        echo ""
        exit 1
    fi
}

function get_latest_version () {
    VERSION=''
    for i in {0..20}; do
        s=$(jq -r ".data[$i].status" < response.txt)
        if [[ $s == *$VERSION_STATUS* ]]; then
            jq -r ".data[$i].version" < response.txt >> versions.txt
        fi
    done
    VERSION=$(sort -t "." -k 1,1 -k 2,2 -k 3,3 -k 4,4 -g versions.txt | tail -n 1)
    echo "The latest version is: $VERSION"
}

function get_latest_version_info () {
    for i in {0..20}; do
        s=$(jq -r ".data[$i].status" < response.txt)
        if [[ $s == *$VERSION_STATUS* ]]; then
            if [[ $(jq -r ".data[$i].version" < response.txt) == "$VERSION" ]]; then
                # VERSION=$(jq -r ".data[$i].version" < response.txt)
                AGENT_FILE_NAME=$(jq -r ".data[$i].fileName" < response.txt)
                AGENT_DOWNLOAD_LINK=$(jq -r ".data[$i].link" < response.txt)
            fi
        fi
    done

    if [[ -z $AGENT_FILE_NAME ]]; then
        printf "\n%sERROR:  Could not obtain AGENT_FILE_NAME in get_latest_version function. %s\n" "${Red}" "${Color_Off}"
        echo ""
        exit 1
    fi
}

# Detect if the Linux Platform uses RPM/DEB packages and the correct Package Manager to use
if grep -q 'ID=ubuntu' /etc/*release || grep -q 'ID=debian' /etc/*release; then
    FILE_EXTENSION='.deb'
    PACKAGE_MANAGER='apt'
    AGENT_INSTALL_SYNTAX='dpkg -i'
elif grep -q 'ID="rhel"' /etc/*release || grep -q 'ID="amzn"' /etc/*release || grep -q 'ID="centos"' /etc/*release || grep -q 'ID="ol"' /etc/*release || grep -q 'ID="scientific"' /etc/*release || grep -q 'ID="rocky"' /etc/*release || grep -q 'ID="almalinux"' /etc/*release; then
    FILE_EXTENSION='.rpm'
    PACKAGE_MANAGER='yum'
    AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
elif grep -q 'ID="sles"' /etc/*release; then
    FILE_EXTENSION='.rpm'
    PACKAGE_MANAGER='zypper'
    AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
elif grep -q 'ID="fedora"' /etc/*release || grep -q 'ID=fedora' /etc/*release; then
    FILE_EXTENSION='.rpm'
    PACKAGE_MANAGER='dnf'
    AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
else
    printf "\n%sERROR:  Unknown Release ID: %s%s\n" "${Red}" "$1" "${Color_Off}"
    cat /etc/*release
    echo ""
fi

curl_check $PACKAGE_MANAGER
# Retrieve AWS_REGION from EC2 Instance Metadata URL
# AWS_REGION=$(TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") && curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/placement/region")
jq_check $PACKAGE_MANAGER
sudo curl -H "Accept: application/json" -H "Authorization: ApiToken $API_KEY" "$S1_MGMT_URL$API_ENDPOINT?countOnly=false&packageTypes=Agent&osTypes=linux&sortBy=createdAt&limit=20&fileExtension=$FILE_EXTENSION&sortOrder=desc" -o response.txt
check_api_response
get_latest_version
get_latest_version_info
printf "\n%sINFO:  Downloading %s%s\n" "${Yellow}" "$AGENT_FILE_NAME" "${Color_Off}"
sudo curl -H "Authorization: ApiToken $API_KEY" "$AGENT_DOWNLOAD_LINK" -o "/tmp/$AGENT_FILE_NAME"
printf "\n%sINFO:  Installing S1 Agent: %s%s\n" "${Yellow}" "sudo $AGENT_INSTALL_SYNTAX /tmp/$AGENT_FILE_NAME" "${Color_Off}"
read -r -a AGENT_INSTALL_COMMAND <<< "$AGENT_INSTALL_SYNTAX"
sudo "${AGENT_INSTALL_COMMAND[@]}" "/tmp/$AGENT_FILE_NAME"
printf "\n%sINFO:  Setting Site Token...%s\n" "${Yellow}" "${Color_Off}"
sudo /opt/sentinelone/bin/sentinelctl management token set "$SITE_TOKEN"
printf "\n%sINFO:  Starting Agent...%s\n" "${Yellow}" "${Color_Off}"
sudo /opt/sentinelone/bin/sentinelctl control start

# Clean up files
printf "\n%sINFO:  Cleaning up files...%s\n" "${Yellow}" "${Color_Off}"
rm -f response.txt
rm -f versions.txt
rm -f "/tmp/$AGENT_FILE_NAME"

printf "\n%sSUCCESS:  Finished installing SentinelOne Agent.%s\n\n" "${Green}" "${Color_Off}"
