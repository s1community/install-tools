#!/bin/bash
##################################################################################################################################
# Description:  Bash script to aid with automating S1 Linux Agent install via AWS Systems Manager and EC2 Image Builder
#
# Pre-requisites: Build instances must have IAM permissions (ie: AmazonSSMManagedInstanceCore + EC2InstanceProfileForImageBuilder)
# 
# Version:  2024.04.17
##################################################################################################################################


# NOTE:  This script will install the latest EA or GA version of the SentinelOne Linux agent and set a Site Token.
# NOTE:  This script WILL NOT ACTIVATE the agent in order to avoid duplicate UUIDs from AMI builds.
# NOTE:  This script will install the curl, jq and awscli utilities if not already installed.

# References:
# - https://docs.aws.amazon.com/imagebuilder/latest/userguide/what-is-image-builder.html
# - https://docs.aws.amazon.com/imagebuilder/latest/userguide/start-build-image-pipeline.html


# Retrieve AWS_REGION from EC2 Instance Metadata URL
AWS_REGION=$(TOKEN=`curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` && curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

S1_MGMT_URL=''
API_KEY=''
SITE_TOKEN=''
VERSION_STATUS=''
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
function check_root () {
    if [[ $(/usr/bin/id -u) -ne 0 ]]; then
        printf "\n${Red}ERROR:  This script must be run as root.  Please retry with 'sudo'.${Color_Off}\n"
        exit 1;
    fi
}

function get_parameter_store_values () {
    # Retrieve values from Systems Manager Parameter Store
    S1_MGMT_URL=$(aws ssm get-parameters --names S1_MGMT_URL --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)
    API_KEY=$(aws ssm get-parameters --names S1_API_KEY --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)
    SITE_TOKEN=$(aws ssm get-parameters --names S1_SITE_TOKEN --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)
    VERSION_STATUS=$(aws ssm get-parameters --names S1_VERSION_STATUS --with-decryption --region $AWS_REGION --query "Parameters[*].Value" --output text)   # "EA" or "GA"
}

function check_args () {
    # Check if the SITE_TOKEN is in the right format
    if ! [[ ${#SITE_TOKEN} -gt 90 ]]; then
        printf "\n${Red}ERROR:  Invalid format for SITE_TOKEN: $SITE_TOKEN ${Color_Off}\n"
        echo "Site Tokens are generally more than 90 characters long and are ASCII encoded."
        echo ""
        exit 1
    fi

    # Check if the API_KEY is in the right format
    if [[ ${#API_KEY} -lt 80 ]]; then
        printf "\n${Red}ERROR:  Invalid format for API_KEY: $API_KEY ${Color_Off}\n"
        echo "API Keys are generally 80 to 430 characters long and are alphanumeric."
        echo ""
        exit 1
    fi

    # Check VERSION_STATUS for valid values and make sure that the value is in lowercase
    VERSION_STATUS=$(echo $VERSION_STATUS | tr [A-Z] [a-z])
    if [[ ${VERSION_STATUS} != *"ga"* && "$VERSION_STATUS" != *"ea"* ]]; then
        printf "\n${Red}ERROR:  Invalid format for VERSION_STATUS: $VERSION_STATUS ${Color_Off}\n"
        echo "The value of VERSION_STATUS must contain either 'ea' or 'ga'"
        echo ""
        exit 1
    fi
}

# Detect if the Linux Platform uses RPM/DEB packages and the correct Package Manager to use
function detect_pkg_mgr_info () {
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
}

# Check if curl is installed.
function curl_check () {
    if ! [[ -x "$(which curl)" ]]; then
        printf "\n${Yellow}INFO:  Installing curl utility in order to interact with S1 API... ${Color_Off}\n"
        if [[ $1 = 'apt' ]]; then
            sudo apt-get update && sudo apt-get install -y curl
        elif [[ $1 = 'yum' ]]; then
            sudo yum install -y curl
        elif [[ $1 = 'zypper' ]]; then
            sudo zypper install -y curl
        elif [[ $1 = 'dnf' ]]; then
            sudo dnf install -y curl
        else
            printf "\n${Red}ERROR:  Unsupported file extension.${Color_Off}\n"
        fi
    else
        printf "\n${Yellow}INFO:  curl is already installed.${Color_Off}\n"
    fi
}

function jq_check () {
    if ! [[ -x "$(which jq)" ]]; then
        printf "\n${Yellow}INFO:  Installing jq utility in order to parse json responses from api... ${Color_Off}\n"
        if [[ $1 = 'apt' ]]; then
            sudo apt update && sudo apt install -y jq
        elif [[ $1 = 'yum' ]]; then
            sudo yum install -y jq
        elif [[ $1 = 'zypper' ]]; then
            sudo zypper install -y jq
        elif [[ $1 = 'dnf' ]]; then
            sudo dnf install -y jq
        else
            printf "\n${Red}ERROR:  unsupported file extension: $1 ${Color_Off}\n"
        fi 
    else
        printf "\n${Yellow}INFO:  jq is already installed.${Color_Off}\n"
    fi
}

function unzip_check () {
    if ! [[ -x "$(which unzip)" ]]; then
        printf "\n${Yellow}INFO:  Installing unzip utility in order to install awscli... ${Color_Off}\n"
        if [[ $1 = 'apt' ]]; then
            sudo apt-get update && sudo apt-get install -y unzip
        elif [[ $1 = 'yum' ]]; then
            sudo yum install -y unzip
        elif [[ $1 = 'zypper' ]]; then
            sudo zypper install -y unzip
        elif [[ $1 = 'dnf' ]]; then
            sudo dnf install -y unzip
        else
            printf "\n${Red}ERROR:  unsupported file extension: $1 ${Color_Off}\n"
        fi 
    else
        printf "\n${Yellow}INFO:  unzip is already installed.${Color_Off}\n"
    fi
}

function awscli_check () {
    if ! [[ -x "$(which aws)" ]]; then
        printf "\n${Yellow}INFO:  Installing awscli utility in order to communicate with Systems Manager Parameter Store... ${Color_Off}\n"     
        if [[ $1 = 'apt' ]]; then
            sudo apt update && sudo apt install -y awscli
        elif [[ $1 = 'yum' ]]; then
            unzip_check  $PACKAGE_MANAGER
            OS_ARCH=$(uname -p)
            if [[ $OS_ARCH == "x86_64" ]]; then
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                unzip awscliv2.zip
            elif [[ $OS_ARCH == "aarch64" ]]; then
                curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
                unzip awscliv2.zip
            else
                printf "\n${Red}ERROR:  OS_ARCH is neither 'aarch64' nor 'x86_64':  $OS_ARCH ${Color_Off}\n"
            fi
            sudo ./aws/install --bin-dir /usr/bin --update
        elif [[ $1 = 'zypper' ]]; then
            sudo zypper install -y awscli
        elif [[ $1 = 'dnf' ]]; then
            sudo dnf install -y awscli
        else
            printf "\n${Red}ERROR:  unsupported file extension: $1 ${Color_Off}\n"
        fi 
    else
        printf "\n${Yellow}INFO:  awscli is already installed.${Color_Off}\n"
    fi
}

function check_api_response () {
    if [[ $(cat response.txt | jq 'has("errors")') == 'true' ]]; then
        printf "\n${Red}ERROR:  Could not authenticate using the existing mgmt server and api key. ${Color_Off}\n"
        echo ""
        exit 1
    fi
}


function find_agent_info_by_architecture () {
    OS_ARCH=$(uname -p)
    if [[ $OS_ARCH == "aarch64" ]]; then
        for i in {0..20}; do
            FN=$(cat response.txt | jq -r ".data[$i].fileName")
            if [[ $FN == *$OS_ARCH* ]]; then
                AGENT_FILE_NAME=$(cat response.txt | jq -r ".data[$i].fileName")
                AGENT_DOWNLOAD_LINK=$(cat response.txt | jq -r ".data[$i].link")
                break
            fi
        done
    elif [[ $OS_ARCH == "x86_64" ]]; then
        for i in {0..20}; do
            FN=$(cat response.txt | jq -r ".data[$i].fileName")
            if [[ $FN != *"aarch"* ]]; then
                AGENT_FILE_NAME=$(cat response.txt | jq -r ".data[$i].fileName")
                AGENT_DOWNLOAD_LINK=$(cat response.txt | jq -r ".data[$i].link")
                break
            fi
        done
    else
        printf "\n${Red}ERROR:  OS_ARCH is neither 'aarch64' nor 'x86_64':  $OS_ARCH ${Color_Off}\n"
    fi

    if [[ $AGENT_FILE_NAME = '' ]]; then
        printf "\n${Red}ERROR:  Could not obtain AGENT_FILE_NAME in find_agent_info_by_architecture function. ${Color_Off}\n"
        echo ""
        exit 1
    fi
}


check_root
detect_pkg_mgr_info
awscli_check $PACKAGE_MANAGER
get_parameter_store_values
check_args
curl_check $PACKAGE_MANAGER
jq_check $PACKAGE_MANAGER
sudo curl -sH "Accept: application/json" -H "Authorization: ApiToken $API_KEY" "$S1_MGMT_URL$API_ENDPOINT?countOnly=false&packageTypes=Agent&osTypes=linux&sortBy=createdAt&limit=20&fileExtension=$FILE_EXTENSION&sortOrder=desc" > response.txt
check_api_response
find_agent_info_by_architecture
printf "\n${Yellow}INFO:  Downloading $AGENT_FILE_NAME ${Color_Off}\n"
sudo curl -sH "Authorization: ApiToken $API_KEY" $AGENT_DOWNLOAD_LINK -o /tmp/$AGENT_FILE_NAME
printf "\n${Yellow}INFO:  Installing S1 Agent: $(echo "sudo $AGENT_INSTALL_SYNTAX /tmp/$AGENT_FILE_NAME") ${Color_Off}\n"
sudo $AGENT_INSTALL_SYNTAX /tmp/$AGENT_FILE_NAME
printf "\n${Yellow}INFO:  Setting Site Token... ${Color_Off}\n"
sudo /opt/sentinelone/bin/sentinelctl management token set $SITE_TOKEN


#clean up files..
printf "\n${Yellow}INFO:  Cleaning up files... ${Color_Off}\n"
rm -f response.txt
rm -f versions.txt
rm -f /tmp/$AGENT_FILE_NAME

printf "\n${Green}SUCCESS:  Finished installing SentinelOne Agent. ${Color_Off}\n\n"
