#!/bin/bash
##############################################################################################################
# Description:  Bash script to aid with automating SentinelOne Linux Agent installation via API
# 
# Usage:    sudo ./s1-agent-install-mgmt-api.sh S1_CONSOLE_PREFIX API_TOKEN SITE_TOKEN VERSION_STATUS
# 
# Version:  1.1
##############################################################################################################

# NOTE:  This version will install the latest EA or GA version of the SentinelOne Linux Agent
# NOTE:  This script will install the curl and jq utilities if not already installed.


S1_MGMT_URL="https://$1.sentinelone.net"    #ie:  usea1-purple
API_ENDPOINT='/web/api/v2.1/update/agent/packages'
API_TOKEN=$2
SITE_TOKEN=$3
VERSION_STATUS=$4   # "EA" or "GA"
CURL_OPTIONS='--silent --tlsv1.2'
FILE_EXTENSION=''
PACKAGE_MANAGER=''
AGENT_INSTALL_SYNTAX=''
AGENT_FILE_NAME=''
AGENT_DOWNLOAD_LINK=''
AGENT_FILE_SHA1=''
VERSION_COMPARE_RESULT=''

Color_Off='\033[0m'       # Text Resets
# Regular Colors
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow

# Check if correct # of arguments are passed.
if [ "$#" -ne 4 ]; then
    printf "\n${Red}ERROR:  Incorrect number of arguments were passed.${Color_Off}\n"
    echo "Usage: $0 S1_CONSOLE_PREFIX API_TOKEN SITE_TOKEN VERSION_STATUS" >&2
    echo ""
    exit 1
fi

# Check if running as root
function check_root () {
    if [[ $(/usr/bin/id -u) -ne 0 ]]; then
        printf "\n${Red}ERROR:  This script must be run as root.  Please retry with 'sudo'.${Color_Off}\n"
        exit 1;
    fi
}


function check_args () {
    # Check if the SITE_TOKEN is in the right format
    if ! [[ ${#SITE_TOKEN} -gt 90 ]]; then
        printf "\n${Red}ERROR:  Invalid format for SITE_TOKEN: $SITE_TOKEN ${Color_Off}\n"
        echo "Site Tokens are generally more than 90 characters long and are ASCII encoded."
        echo ""
        exit 1
    fi

    # Check if the API_TOKEN is in the right format
    if ! [[ ${#API_TOKEN} -gt 79 ]] ; then
        printf "\n${Red}ERROR:  Invalid format for API_TOKEN: $API_TOKEN ${Color_Off}\n"
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
            printf "\n${Red}ERROR:  Unsupported package manager: $1.${Color_Off}\n"
        fi
    else
        printf "\n${Yellow}INFO:  curl is already installed.${Color_Off}\n"
    fi
}


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


function find_agent_info_by_architecture () {
    OS_ARCH=$(uname -p)
    if [[ $OS_ARCH == "aarch64" ]]; then
        for i in {0..20}; do
            FN=$(cat response.txt | jq -r ".data[$i].fileName")
            if [[ $FN == *$OS_ARCH* ]]; then
                AGENT_FILE_NAME=$(cat response.txt | jq -r ".data[$i].fileName")
                AGENT_DOWNLOAD_LINK=$(cat response.txt | jq -r ".data[$i].link")
                AGENT_FILE_SHA1=$(cat response.txt | jq -r ".data[$i].sha1")
                break
            fi
        done
    elif [[ $OS_ARCH == "x86_64" || $OS_ARCH == "unknown" ]]; then
        for i in {0..20}; do
            FN=$(cat response.txt | jq -r ".data[$i].fileName")
            if [[ $FN != *"aarch"* ]]; then
                AGENT_FILE_NAME=$(cat response.txt | jq -r ".data[$i].fileName")
                AGENT_DOWNLOAD_LINK=$(cat response.txt | jq -r ".data[$i].link")
                AGENT_FILE_SHA1=$(cat response.txt | jq -r ".data[$i].sha1")
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


# Validate agent metadata returned by the management API before using it as a
# path component or shell argument.  Without these checks, a tampered API
# response could traverse out of /tmp, inject curl flags, or pass an option
# through to dpkg/rpm.
function validate_agent_info () {
    if [[ "$AGENT_FILE_NAME" != "$(basename -- "$AGENT_FILE_NAME")" ]] \
        || [[ "$AGENT_FILE_NAME" == *".."* ]] \
        || ! [[ "$AGENT_FILE_NAME" =~ ^[A-Za-z0-9._-]+\.(deb|rpm)$ ]]; then
        printf "\n${Red}ERROR:  Refusing to use untrusted agent file name returned by API: %s ${Color_Off}\n" "$AGENT_FILE_NAME"
        exit 1
    fi

    # Download URL must be HTTPS so a tampered API response cannot redirect to
    # a non-TLS or non-HTTP scheme.  The host is not restricted because
    # SentinelOne may serve packages from a CDN; integrity is enforced via
    # the SHA1 check below instead.
    if ! [[ "$AGENT_DOWNLOAD_LINK" =~ ^https://[^[:space:]]+$ ]]; then
        printf "\n${Red}ERROR:  Refusing to download from non-HTTPS agent download link: %s ${Color_Off}\n" "$AGENT_DOWNLOAD_LINK"
        exit 1
    fi

    if ! [[ "$AGENT_FILE_SHA1" =~ ^[a-fA-F0-9]{40}$ ]]; then
        printf "\n${Red}ERROR:  Refusing to install agent without a valid SHA1 from the API: %s ${Color_Off}\n" "$AGENT_FILE_SHA1"
        exit 1
    fi
}


# Verify the downloaded package matches the SHA1 returned by the management
# API.
function verify_agent_sha1 () {
    local expected actual
    expected=$(printf '%s' "$AGENT_FILE_SHA1" | tr '[:upper:]' '[:lower:]')
    actual=$(sha1sum -- "/tmp/$AGENT_FILE_NAME" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    if [[ "$actual" != "$expected" ]]; then
        printf "\n${Red}ERROR:  SHA1 mismatch on downloaded agent.  expected=%s actual=%s ${Color_Off}\n" "$expected" "$actual"
        rm -f -- "/tmp/$AGENT_FILE_NAME"
        exit 1
    fi
    printf "\n${Yellow}INFO:  SHA1 verified: %s ${Color_Off}\n" "$actual"
}


# Detect if the Linux Platform uses RPM/DEB packages and the correct Package Manager to use
function detect_pkg_mgr_info () {
    if (cat /etc/os-release | grep -E "ID=(ubuntu|debian)" &> /dev/null ); then
        FILE_EXTENSION='.deb'
        PACKAGE_MANAGER='apt'
        AGENT_INSTALL_SYNTAX='dpkg -i'
    elif (cat /etc/os-release | grep -E "ID=\"(rhel|amzn|centos|ol|scientific|rocky|almalinux)\"" &> /dev/null ); then
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

check_root
check_args
detect_pkg_mgr_info
curl_check $PACKAGE_MANAGER
jq_check $PACKAGE_MANAGER
sudo curl -sH "Accept: application/json" -H "Authorization: ApiToken $API_TOKEN" "$S1_MGMT_URL$API_ENDPOINT?sortOrder=desc&fileExtension=$FILE_EXTENSION&limit=20&sortBy=version&status=$VERSION_STATUS&platformTypes=linux" > response.txt
check_api_response
find_agent_info_by_architecture
validate_agent_info
printf "\n${Yellow}INFO:  Downloading %s ${Color_Off}\n" "$AGENT_FILE_NAME"
sudo curl -sH "Authorization: ApiToken $API_TOKEN" -o "/tmp/$AGENT_FILE_NAME" -- "$AGENT_DOWNLOAD_LINK"
verify_agent_sha1
printf "\n${Yellow}INFO:  Installing S1 Agent: sudo %s -- /tmp/%s ${Color_Off}\n" "$AGENT_INSTALL_SYNTAX" "$AGENT_FILE_NAME"
sudo $AGENT_INSTALL_SYNTAX -- "/tmp/$AGENT_FILE_NAME"
printf "\n${Yellow}INFO:  Setting Site Token... ${Color_Off}\n"
sudo /opt/sentinelone/bin/sentinelctl management token set "$SITE_TOKEN"
printf "\n${Yellow}INFO:  Starting Agent... ${Color_Off}\n"
sudo /opt/sentinelone/bin/sentinelctl control start

#clean up files..
printf "\n${Yellow}INFO:  Cleaning up files... ${Color_Off}\n"
rm -f response.txt
rm -f versions.txt
rm -f -- "/tmp/$AGENT_FILE_NAME"

printf "\n${Green}SUCCESS:  Finished installing SentinelOne Agent. ${Color_Off}\n\n"