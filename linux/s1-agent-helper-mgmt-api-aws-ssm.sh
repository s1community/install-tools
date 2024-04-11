#!/bin/bash
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
CURL_OPTIONS='--silent --tlsv1.2'
FILE_EXTENSION=''
PACKAGE_MANAGER=''
AGENT_INSTALL_SYNTAX=''
AGENT_FILE_NAME=''
AGENT_DOWNLOAD_LINK=''
VERSION_COMPARE_RESULT=''

Color_Off='\033[0m'       # Text Resets
# Regular Colors
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow


# Check if running as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    printf "\n${Red}ERROR:  This script must be run as root.  Please retry with 'sudo'.${Color_Off}\n"
    exit 1;
fi


# Check if curl is installed.
function curl_check () {
    if ! [[ -x "$(which curl)" ]]; then
        printf "\n${Yellow}INFO:  Installing curl utility in order to interact with S1 API... ${Color_Off}\n"
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
            printf "\n${Red}ERROR:  Unsupported file extension.${Color_Off}\n"
        fi
    else
        printf "${Yellow}INFO:  curl is already installed.${Color_Off}\n"
    fi
}

# Check if the SITE_TOKEN is in the right format
if ! [[ ${#SITE_TOKEN} -gt 90 ]]; then
    printf "\n${Red}ERROR:  Invalid format for SITE_TOKEN: $SITE_TOKEN ${Color_Off}\n"
    echo "Site Tokens are generally more than 90 characters long and are ASCII encoded."
    echo ""
    exit 1
fi

# Check if the API_KEY is in the right format
if ! [[ ${#API_KEY} -gt 79 ]]; then
    printf "\n${Red}ERROR:  Invalid format for API_KEY: $API_KEY ${Color_Off}\n"
    echo "API Keys are generally 80 to 430 characters long and are alphanumeric."
    echo ""
    exit 1
fi

# Check if the VERSION_STATUS is in the right format
VERSION_STATUS=$(echo $S1_VERSION_STATUS | awk '{print tolower($0)}')
if [[ ${VERSION_STATUS} != *"ga"* && "$VERSION_STATUS" != *"ea"* ]]; then
    printf "\n${Red}ERROR:  Invalid format for VERSION_STATUS: $VERSION_STATUS ${Color_Off}\n"
    echo "The value of VERSION_STATUS must contain either 'ea' or 'ga'"
    echo ""
    exit 1
fi


function jq_check () {
    if ! [[ -x "$(which jq)" ]]; then
        printf "\n${Yellow}INFO:  Installing jq utility in order to parse json responses from api... ${Color_Off}\n"
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
            printf "\n${Red}ERROR:  unsupported file extension: $1 ${Color_Off}\n"
        fi 
    else
        printf "${Yellow}INFO:  jq is already installed.${Color_Off}\n"
    fi
}


function check_api_response () {
    if [[ $(cat response.txt | jq 'has("errors")') == 'true' ]]; then
        printf "\n${Red}ERROR:  Could not authenticate using the existing mgmt server and api key. ${Color_Off}\n"
        echo ""
        exit 1
    fi
}


function get_latest_version () {
    VERSION=''
    for i in {0..20}; do
        s=$(cat response.txt | jq -r ".data[$i].status")
        if [[ $s == *$VERSION_STATUS* ]]; then
            echo $(cat response.txt | jq -r ".data[$i].version") >> versions.txt
        fi
    done
    VERSION=$(cat versions.txt | sort -t "." -k 1,1 -k 2,2 -k 3,3 -k 4,4 -g | tail -n 1)
    echo "The latest version is: $VERSION"
}

function get_latest_version_info () {
    for i in {0..20}; do
        s=$(cat response.txt | jq -r ".data[$i].status")
        if [[ $s == *$VERSION_STATUS* ]]; then
            if [[ $(cat response.txt | jq -r ".data[$i].version") == $VERSION ]];then
                #VERSION=$(cat response.txt | jq -r ".data[$i].version")
                AGENT_FILE_NAME=$(cat response.txt | jq -r ".data[$i].fileName")
                AGENT_DOWNLOAD_LINK=$(cat response.txt | jq -r ".data[$i].link")
            fi
        fi
    done

    if [[ $AGENT_FILE_NAME = '' ]]; then
        printf "\n${Red}ERROR:  Could not obtain AGENT_FILE_NAME in get_latest_version function. ${Color_Off}\n"
        echo ""
        exit 1
    fi
}


# Detect if the Linux Platform uses RPM/DEB packages and the correct Package Manager to use
if (cat /etc/*release |grep 'ID=ubuntu' || cat /etc/*release |grep 'ID=debian'); then
    FILE_EXTENSION='.deb'
    PACKAGE_MANAGER='apt'
    AGENT_INSTALL_SYNTAX='dpkg -i'
elif (cat /etc/*release |grep 'ID="rhel"' || cat /etc/*release |grep 'ID="amzn"' || cat /etc/*release |grep 'ID="centos"' || cat /etc/*release |grep 'ID="ol"' || cat /etc/*release |grep 'ID="scientific"' || cat /etc/*release |grep 'ID="rocky"' || cat /etc/*release |grep 'ID="almalinux"'); then
    FILE_EXTENSION='.rpm'
    PACKAGE_MANAGER='yum'
    AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
elif (cat /etc/*release |grep 'ID="sles"'); then
    FILE_EXTENSION='.rpm'
    PACKAGE_MANAGER='zypper'
    AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
elif (cat /etc/*release |grep 'ID="fedora"' || cat /etc/*release |grep 'ID=fedora'); then
    FILE_EXTENSION='.rpm'
    PACKAGE_MANAGER='dnf'
    AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
else
    printf "\n${Red}ERROR:  Unknown Release ID: $1 ${Color_Off}\n"
    cat /etc/*release
    echo ""
fi

curl_check $PACKAGE_MANAGER
# Retrieve AWS_REGION from EC2 Instance Metadata URL
# AWS_REGION=$(TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` && curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/placement/region)
jq_check $PACKAGE_MANAGER
sudo curl -H "Accept: application/json" -H "Authorization: ApiToken $API_KEY" "$S1_MGMT_URL$API_ENDPOINT?countOnly=false&packageTypes=Agent&osTypes=linux&sortBy=createdAt&limit=20&fileExtension=$FILE_EXTENSION&sortOrder=desc" > response.txt
check_api_response
get_latest_version
get_latest_version_info
printf "\n${Yellow}INFO:  Downloading $AGENT_FILE_NAME ${Color_Off}\n"
sudo curl -H "Authorization: ApiToken $API_KEY" $AGENT_DOWNLOAD_LINK -o /tmp/$AGENT_FILE_NAME
printf "\n${Yellow}INFO:  Installing S1 Agent: $(echo "sudo $AGENT_INSTALL_SYNTAX /tmp/$AGENT_FILE_NAME") ${Color_Off}\n"
sudo $AGENT_INSTALL_SYNTAX /tmp/$AGENT_FILE_NAME
printf "\n${Yellow}INFO:  Setting Site Token... ${Color_Off}\n"
sudo /opt/sentinelone/bin/sentinelctl management token set $SITE_TOKEN
printf "\n${Yellow}INFO:  Starting Agent... ${Color_Off}\n"
sudo /opt/sentinelone/bin/sentinelctl control start

#clean up files..
printf "\n${Yellow}INFO:  Cleaning up files... ${Color_Off}\n"
rm -f response.txt
rm -f versions.txt
rm -f /tmp/$AGENT_FILE_NAME

printf "\n${Green}SUCCESS:  Finished installing SentinelOne Agent. ${Color_Off}\n\n"