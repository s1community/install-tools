#!/bin/bash
##############################################################################################################
# Description:  Bash script to aid with automating S1 Agent install on Linux
#
# Usage:  sudo ./s1-agent-install-repo.sh S1_REPOSITORY_USERNAME S1_REPOSITORY_PASSWORD S1_SITE_TOKEN S1_AGENT_VERSION
#
# Notes: This script will install the curl utility on ubuntu / debian systems if not already installed.
#
# Version:  2025.02.20
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

# Example format for 's1.config' file
# S1_REPOSITORY_USERNAME=""
# S1_REPOSITORY_PASSWORD=""
# S1_SITE_TOKEN=""
# S1_AGENT_VERSION="24.3.3.6"
# INCLUDE_EARLY_ACCESS_REPO="true"


# Check for s1.config file.  If it exists, source it.
if [ -f s1.config ]; then
    printf "\n${Yellow}INFO:  Found 's1.config' file in $(pwd).${Color_Off}\n\n"
    source s1.config
else
    printf "\n${Yellow}INFO:  No 's1.config' file found in $(pwd).${Color_Off}\n\n"
fi

# Check if all 4 arguments were passed to the script
if [ $# -eq 4 ] || [ $# -eq 5 ]; then
    printf "\n${Yellow}INFO:  Found $# arguments that were passed to the script. \n\n${Color_Off}"
    S1_REPOSITORY_USERNAME=$1
    S1_REPOSITORY_PASSWORD=$2
    S1_SITE_TOKEN=$3
    S1_AGENT_VERSION=$4
    INCLUDE_EARLY_ACCESS_REPO="${5:-true}"
fi

# Check if arguments have been passed at all.
if [ $# -eq 0 ]; then
    printf "\n${Yellow}INFO:  No input arguments were passed to the script. \n\n${Color_Off}"
fi

# If the 4 needed variables have not been sourced from the s1.config file, passed via cmdline
#   arguments or read from exported variables of the parent shell, we'll prompt the user for them.
if [ -z $S1_REPOSITORY_USERNAME ];then
    echo ""
    read -p "Please enter your SentinelOne Repo Username: " S1_REPOSITORY_USERNAME
fi

if [ -z $S1_REPOSITORY_PASSWORD ];then
    echo ""
    read -p "Please enter your SentinelOne Repo Password: " S1_REPOSITORY_PASSWORD
fi

if [ -z $S1_SITE_TOKEN ];then
    echo ""
    read -p "Please enter your SentinelOne Site Token: " S1_SITE_TOKEN
fi

if [ -z $S1_AGENT_VERSION ];then
    echo ""
    read -p "Please enter the SentinelOne Agent Version to install: " S1_AGENT_VERSION
fi

if [ -z $INCLUDE_EARLY_ACCESS_REPO ];then
    echo ""
    read -p "Would you like to include SentinelOne's Early Access Repo (Yes/No)?: " INCLUDE_EARLY_ACCESS_REPO
fi

################################################################################
# Sanity Check Functions for execution enviornment and variable inputs
################################################################################

# Check if running as root
function check_root () {
    if [[ $(/usr/bin/id -u) -ne 0 ]]; then
        printf "\n${Red}ERROR:  This script must be run as root.  Please retry with 'sudo'.${Color_Off}\n"
        exit 1;
    fi
}

# Sanity check arguments passed to the script
function check_args () {
        # Check if the value of S1_SITE_TOKEN is in the right format
    if ! echo $S1_SITE_TOKEN | base64 -d | grep sentinelone.net &> /dev/null ; then
        printf "\n${Red}ERROR:  Site Token does not decode correctly.  Please ensure that you've passed a valid Site Token as the first argument to the script. \n${Color_Off}"
        printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
        printf "    ${Blue}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n\n"
        exit 1
    fi

    # Check if the value of S1_REPOSITORY_USERNAME is in the right format
    if ! echo $S1_REPOSITORY_USERNAME | base64 -d | grep -E '^[0-9]+\:(aws|gcp)\:[a-zA-Z0-9-]+\:[0-9]{18,19}$' &> /dev/null ; then
        printf "\n${Red}ERROR:  That value passed for S1_REPOSITORY_USERNAME does not decode correctly.  Please ensure that you've passed a valid Registry Username as the second argument to the script. \n${Color_Off}"
        printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
        printf "    ${Blue}https://community.sentinelone.com/s/article/000008771 ${Color_Off} \n\n"
        exit 1
    fi

    # Check if the value of S1_REPOSITORY_PASSWORD is in the right format
    if ! [ ${#S1_REPOSITORY_PASSWORD} -gt 160 ]; then
        printf "\n${Red}ERROR:  That value passed for S1_REPOSITORY_PASSWORD did not pass a basic length test (longer than 160 characters).  Please ensure that you've passed a valid Registry Password as the second argument to the script. \n${Color_Off}"
        printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
        printf "    ${Blue}https://community.sentinelone.com/s/article/000008771 ${Color_Off} \n\n"
        exit 1
    fi

    # Check if the value of S1_AGENT_VERSION is in the right format
    if ! echo $S1_AGENT_VERSION | grep -E '^[0-9]{2}\.[0-9]\.[0-9]\.[0-9]+$' &> /dev/null ; then
        printf "\n${Red}ERROR:  The value passed for S1_AGENT_VERSION is not in the correct format.  Examples of valid values are:  23.3.2.12 and 23.4.1.4 \n\n${Color_Off}"
        exit 1
    fi

}

# Determine the CPU architecture
function find_agent_info_by_architecture () {
    OS_ARCH=$(uname -p)
    if [[ $OS_ARCH == "aarch64" ]]; then
        printf "\n${Yellow}INFO:  CPU Architecture is $OS_ARCH... ${Color_Off} \n\n"
    elif [[ $OS_ARCH == "x86_64" || $OS_ARCH == "unknown" ]]; then
        OS_ARCH="x86_64" # for cases when uname -p returns "unknown" (ie: Some versions of Fedora), we'll assume x86_64.
        printf "\n${Yellow}INFO:  CPU Architecture is $OS_ARCH... ${Color_Off} \n\n"
    else
        printf "\n${Red}ERROR:  OS_ARCH is neither 'aarch64' nor 'x86_64':  $OS_ARCH ${Color_Off}\n"
    fi
}


################################################################################
# Functions to detect the OS and install using the correct package manager
################################################################################

# Detect the correct Package Manager to use given the Operating System's ID
function detect_pkg_mgr_info () {
    if (cat /etc/os-release | grep -E "ID=(ubuntu|debian)" &> /dev/null ); then
        printf "\n${Yellow}INFO:  Detected Debian-based OS...${Color_Off} \n\n"
        install_using_apt
    elif (cat /etc/os-release | grep -E "ID=\"(rhel|amzn|centos|ol|scientific|rocky|almalinux)\"" &> /dev/null ); then
        printf "\n${Yellow}INFO:  Detected Red Hat-based OS...${Color_Off} \n\n"
        install_using_yum_or_dnf
    elif (cat /etc/os-release |grep 'ID="fedora"' || cat /etc/os-release |grep 'ID=fedora' &> /dev/null ); then
        printf "\n${Yellow}INFO:  Detected Red Hat-based OS...${Color_Off} \n\n"
        install_using_yum_or_dnf
    else
        printf "\n${Red}ERROR:  Unknown Release ID: $1 ${Color_Off}\n"
        cat /etc/*release
        echo ""
        exit 1
    fi
}


function install_using_apt () {
    printf "\n${Yellow}INFO:  Installing with apt...${Color_Off} \n\n"
    S1_REPOSITORY_URL="deb.sentinelone.net"
    # ensure curl is installed before downloading signing keys
    if ! (which curl &> /dev/null); then
        printf "\n${Yellow}INFO:  Installing curl utility in order to download gpg keys... ${Color_Off}\n"
        apt-get update
        apt-get install -y curl
        if [ $? -ne 0 ]; then
            printf "\n${Red}ERROR:  Unable to install required dependency curl.${Color_Off}\n"
            exit 1
        fi
    fi

    # add public signature verification key for the repository to ensure the integrity and authenticity of packages
    # requires gpg, otherwise use fallback method below for bionic|buster
    if (which gpg &> /dev/null); then
        set -x
        curl -sL https://${S1_REPOSITORY_URL}/v1/gpg/package-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sentinelone-package-key.gpg
        curl -sL https://${S1_REPOSITORY_URL}/v1/gpg/repo-key.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sentinelone-repo-key.gpg
        set +x
    fi
    # remove any existing source lists for sentinelone
    rm -f /etc/apt/sources.list.d/sentinelone-repository-ga.list
    rm -f /etc/apt/sources.list.d/sentinelone-repository-ea.list

    if (cat /etc/os-release | grep -E "VERSION_CODENAME=(bionic|buster)" &> /dev/null ); then
        printf "\n${Yellow}INFO:  Detected Bionic Beaver or Buster.  Using older GPG/Auth methods...${Color_Off} \n\n"
        # add public signature verification key for the repository to ensure the integrity and authenticity of packages
        curl -sL  https://${S1_REPOSITORY_URL}/v1/gpg/package-key.gpg | apt-key add - && curl -sL https://${S1_REPOSITORY_URL}/v1/gpg/repo-key.gpg | apt-key add -
        # add the GA repository to the list of sources
        cat <<- EOF > /etc/apt/sources.list.d/sentinelone-repository-ga.list
deb [trusted=yes] https://${S1_REPOSITORY_USERNAME}:${S1_REPOSITORY_PASSWORD}@${S1_REPOSITORY_URL}/apt-ga apt-ga main
EOF
        if ( echo $INCLUDE_EARLY_ACCESS_REPO | grep -E "([Tt]rue|[Yy]es|[Yy])" &> /dev/null ); then
            # add the EA repository to the list of sources (if INCLUDE_EARLY_ACCESS_REPO is set to true)
            cat <<- EOF > /etc/apt/sources.list.d/sentinelone-repository-ea.list
deb [trusted=yes] https://${S1_REPOSITORY_USERNAME}:${S1_REPOSITORY_PASSWORD}@${S1_REPOSITORY_URL}/apt-ea apt-ea main
EOF
        fi
    else
        # add the GA repository to the list of sources
        cat <<- EOF > /etc/apt/sources.list.d/sentinelone-repository-ga.list
deb [trusted=yes] https://${S1_REPOSITORY_URL}/apt-ga apt-ga main
EOF
        if ( echo $INCLUDE_EARLY_ACCESS_REPO | grep -E "([Tt]rue|[Yy]es|[Yy])" &> /dev/null ); then
            # add the EA repository to the list of sources (if INCLUDE_EARLY_ACCESS_REPO is set to true)
            cat <<- EOF > /etc/apt/sources.list.d/sentinelone-repository-ea.list
deb [trusted=yes] https://${S1_REPOSITORY_URL}/apt-ea apt-ea main
EOF
        fi
        # add repo credentials to /etc/apt/auth.conf.d for the SentinelOne repo
        cat <<- EOF >> /etc/apt/auth.conf.d/sentinelone-repository.conf
machine ${S1_REPOSITORY_URL}
login ${S1_REPOSITORY_USERNAME}
password ${S1_REPOSITORY_PASSWORD}
EOF
    fi
    apt update
    apt install -y sentinelagent=${S1_AGENT_VERSION}
}


function install_using_yum_or_dnf () {
    printf "\n${Yellow}INFO:  Installing with yum or dnf...${Color_Off} \n\n"
    S1_REPOSITORY_URL="rpm.sentinelone.net"
    # add public signature verification key for the repository to ensure the integrity and authenticity of packages
    rpm --import https://${S1_REPOSITORY_URL}/v1/gpg/package-key.gpg
    # Check if we're working with Amazon Linux 2.  If so, use a different auth format for the repos
    if (grep -E '^PRETTY_NAME="Amazon Linux 2"$' /etc/os-release &> /dev/null ); then
        printf "\n${Yellow}INFO:  Detected Amazon Linux 2.  Using older Auth methods...${Color_Off} \n\n"
        # add the GA repository to the list of sources
        cat <<- EOF > /etc/yum.repos.d/sentinelone-repository-ga.repo
[yum-ga]
name=yum-ga
baseurl=https://${S1_REPOSITORY_USERNAME}:${S1_REPOSITORY_PASSWORD}@${S1_REPOSITORY_URL}/yum-ga
enabled=1
repo_gpgcheck=0
gpgcheck=0
EOF
        if (echo $INCLUDE_EARLY_ACCESS_REPO | grep -E "([Tt]rue|[Yy]es|[Yy])" &> /dev/null ); then
            # add the EA repository to the list of sources (if INCLUDE_EARLY_ACCESS_REPO is set to true)
            cat <<- EOF > /etc/yum.repos.d/sentinelone-repository-ea.repo
[yum-ea]
name=yum-ea
baseurl=https://${S1_REPOSITORY_USERNAME}:${S1_REPOSITORY_PASSWORD}@${S1_REPOSITORY_URL}/yum-ea
enabled=1
repo_gpgcheck=0
gpgcheck=0
EOF
        fi
    else
        # add the GA repository to the list of sources
        cat <<- EOF > /etc/yum.repos.d/sentinelone-repository-ga.repo
[yum-ga]
name=yum-ga
baseurl=https://${S1_REPOSITORY_URL}/yum-ga
enabled=1
repo_gpgcheck=0
gpgcheck=0
username=${S1_REPOSITORY_USERNAME}
password=${S1_REPOSITORY_PASSWORD}
EOF
        # add the EA repository to the list of sources (if INCLUDE_EARLY_ACCESS_REPO is set to true)
        if ( echo $INCLUDE_EARLY_ACCESS_REPO | grep -E "([Tt]rue|[Yy]es|[Yy])" &> /dev/null ); then
            cat <<- EOF > /etc/yum.repos.d/sentinelone-repository-ea.repo
[yum-ea]
name=yum-ea
baseurl=https://${S1_REPOSITORY_URL}/yum-ea
enabled=1
repo_gpgcheck=0
gpgcheck=0
username=${S1_REPOSITORY_USERNAME}
password=${S1_REPOSITORY_PASSWORD}
EOF
        fi
    fi

    # Check if dnf is available, if not.. use yum.
    if (which dnf &> /dev/null); then
            dnf makecache
            dnf install -y SentinelAgent-${S1_AGENT_VERSION}-1.${OS_ARCH}
        else
            yum makecache
            yum install -y SentinelAgent-${S1_AGENT_VERSION}-1.${OS_ARCH}
    fi

}

################################################################################
# Call functions to install the SentinelOne Agent
################################################################################

# Run functions
check_root
check_args
find_agent_info_by_architecture
detect_pkg_mgr_info
if [ $? -eq 0 ]; then
    printf "\n${Green}SUCCESS:  Finished installing SentinelOne Agent package ${Color_Off}\n\n"
else
    printf "\n${Red}ERROR:  Failed to install SentinelOne Agent. ${Color_Off}\n\n"
    exit 1
fi


################################################################################
# Configure and Start the SentinelOne Agent
################################################################################

# Set the Site Token
sentinelctl management token set $S1_SITE_TOKEN

# Start the Agent
sentinelctl control start
