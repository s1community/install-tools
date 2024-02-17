#!/bin/bash
##############################################################################################################
# Description:  Bash script to pull container images from SentinelOne public repo and push to a 
#               private repository.
#
#               Either copy s1.config.example to s1.config and update variables, 
#               run the script with no arguments to be prompted for values, or
#               pass all arguments at the command line.
# 
#
# Usage:  ./s1-pull-private-push.sh
# Usage:  ./s1-pull-private-push.sh S1_REPOSITORY_USERNAME S1_REPOSITORY_PASSWORD S1_AGENT_TAG \
#           PRIVATE_REPO_BASE PRIVATE_REPO_AGENT_NAME PRIVATE_REPO_HELPER_NAME
# 
# Version:  1.0
#
# Reference:  https://community.sentinelone.com/s/article/000008772
#
# NOTE: Log into your private registry before running this script.  If you do not log into the 
#       docker cli, the push will fail.
#
# NOTE: Please be aware that there is a 100 pulls/hour rate limit for the SentinelOne repository!!
#
# NOTE: Many registries support the creation of an image repository on push.  AWS ECR does not.
#       If pushing to AWS ECR, you MUST pre-create the repositories designated by
#       PRIVATE_REPO_AGENT_NAME and PRIVATE_REPO_HELPER_NAME before running this script.
#
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
# Global Variables
################################################################################
# The following variables SHOULD NOT BE ALTERED
S1_REPO_BASE="containers.sentinelone.net"
S1_REPO_AGENT="${S1_REPO_BASE}/cws-agent/s1agent"
S1_REPO_HELPER="${S1_REPO_BASE}/cws-agent/s1helper"

################################################################################
# Gather Inputs
################################################################################

# Check for s1.config file.  If it exists, source it.
if [ -f s1.config ]; then
    printf "\n${Yellow}INFO:  Found 's1.config' file in $(pwd).${Color_Off}\n\n"
    source s1.config
else
    printf "\n${Yellow}INFO:  No 's1.config' file found in $(pwd).${Color_Off}\n\n"
fi 

# Check if all 6 arguments were passed to the script
if [ $# -eq 6 ] ; then
    printf "\n${Yellow}INFO:  Found $# arguments that were passed to the script. \n\n${Color_Off}"
    S1_REPOSITORY_USERNAME=$1
    S1_REPOSITORY_PASSWORD=$2
    S1_AGENT_TAG=$3
    PRIVATE_REPO_BASE=$4
    PRIVATE_REPO_AGENT_NAME=$5
    PRIVATE_REPO_HELPER_NAME=$6
fi

# Check if arguments have been passed at all.
if [ $# -eq 0 ]; then
    printf "\n${Yellow}INFO:  No input arguments were passed to the script. \n\n${Color_Off}"
fi

if [ -z $S1_REPOSITORY_USERNAME ];then
    echo ""
    read -p "Please enter your SentinelOne Repo Username: " S1_REPOSITORY_USERNAME
fi

if [ -z $S1_REPOSITORY_PASSWORD ];then
    echo ""
    read -p "Please enter your SentinelOne Repo Password: " S1_REPOSITORY_PASSWORD
fi

if [ -z $S1_AGENT_TAG ];then
    echo ""
    read -p "Please enter the SentinelOne Agent Version Tag to install (ie: 23.4.2-ga): " S1_AGENT_VERSION
fi

if [ -z $PRIVATE_REPO_BASE ];then
    echo ""
    read -p "Please enter the destination registry URI (ie: your.registry.tld): " PRIVATE_REPO_BASE
fi

if [ -z $PRIVATE_REPO_AGENT_NAME ];then
    echo ""
    read -p "Please enter the destination agent repository name (ie: s1agent): " PRIVATE_REPO_AGENT_NAME
fi

if [ -z $PRIVATE_REPO_HELPER_NAME ];then
    echo ""
    read -p "Please enter the destination helper repository name (ie: s1helper): " PRIVATE_REPO_HELPER_NAME
fi

################################################################################
# Sanity Check the execution environment 
################################################################################

# Check for prerequisite binaries
if ! command -v docker &> /dev/null ; then
    printf "\n${Red}Missing the 'docker' engine.  Please install this utility and try again.\n"
    printf "Reference:  https://docs.docker.com/engine/install/\n${Color_Off}"
    exit 1
fi

################################################################################
# Sanity Check the variable inputs
################################################################################

# Check if the value of S1_REPOSITORY_USERNAME is in the right format
if ! echo $S1_REPOSITORY_USERNAME | base64 -d | grep -E '^[[:digit:]]+\:(aws|gcp)\:[a-zA-Z0-9-]+\:[a-zA-Z0-9-]+$' &> /dev/null ; then
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

# Check if the value of S1_AGENT_TAG is in the right format
if ! echo $S1_AGENT_TAG | grep -E '^[[:digit:]][[:digit:]]\.[[:digit:]]\.[[:digit:]]-[ge]a$' &> /dev/null ; then
    printf "\n${Red}ERROR:  The value passed for S1_AGENT_TAG is not in the correct format.  Examples of valid values are:  23.3.2-ga and 23.4.1-ea \n\n${Color_Off}"
    exit 1
fi

################################################################################
# Separate tag into version and release
################################################################################

S1_AGENT_VERSION=$(echo $S1_AGENT_TAG | cut -d "-" -f1)
S1_AGENT_RELEASE=$(echo $S1_AGENT_TAG | cut -d "-" -f2)

################################################################################
# Ensure Agent and Helper have the same version
################################################################################

S1_HELPER_VERSION=$S1_AGENT_VERSION
S1_HELPER_RELEASE=$S1_AGENT_RELEASE

################################################################################
# Generate all manifest and architecture tag variations
################################################################################

S1_HELPER_TAG="${S1_AGENT_TAG}"

S1_AGENT_TAG_x86_64=${S1_AGENT_VERSION}-x86_64-${S1_AGENT_RELEASE}
S1_AGENT_TAG_aarch64=${S1_AGENT_VERSION}-aarch64-${S1_AGENT_RELEASE}

S1_HELPER_TAG_x86_64=${S1_HELPER_VERSION}-x86_64-${S1_HELPER_RELEASE}
S1_HELPER_TAG_aarch64=${S1_HELPER_VERSION}-aarch64-${S1_HELPER_RELEASE}

################################################################################
# Generate full private registry name for agent and helper destinations
################################################################################

PRIVATE_REPO_AGENT="${PRIVATE_REPO_BASE}/${PRIVATE_REPO_AGENT_NAME}"
PRIVATE_REPO_HELPER="${PRIVATE_REPO_BASE}/${PRIVATE_REPO_HELPER_NAME}"

################################################################################
# exit on error from this point forward
################################################################################

set -e

################################################################################
# Log into SentinelOne repository
################################################################################

# ignore WARNING from docker
# the password is stored in a flat file and passing it directly to the login 
# command is no less secure
printf "\n${Yellow}INFO:  Logging into SentinelOne Repository \n\n${Color_Off}"
docker login ${S1_REPO_BASE} -u ${S1_REPOSITORY_USERNAME} -p ${S1_REPOSITORY_PASSWORD} 2>/dev/null
if [ $? -eq 0 ]; then
    printf "\n${Green}Succesfully logged into docker cli! ${Color_Off}\n"
else
    printf "\n${Red}ERROR:  Could not log into docker cli. ${Color_Off}\n"
    exit 1
fi

################################################################################
# Pull all images from the SentinelOne Public Registry
################################################################################

# agent
printf "\n${Yellow}INFO:  Pulling agent images from SentinelOne Repository \n\n${Color_Off}"
docker image pull ${S1_REPO_AGENT}:${S1_AGENT_TAG_x86_64}
docker image pull ${S1_REPO_AGENT}:${S1_AGENT_TAG_aarch64}

# helper
printf "\n${Yellow}INFO:  Pulling helper images from SentinelOne Repository \n\n${Color_Off}"
docker image pull ${S1_REPO_HELPER}:${S1_HELPER_TAG_x86_64}
docker image pull ${S1_REPO_HELPER}:${S1_HELPER_TAG_aarch64}

################################################################################
# Retag all images to prepare to push to private registry
################################################################################

# agent
printf "\n${Yellow}INFO:  Tagging agent images in private repository ${PRIVATE_REPO_AGENT} \n\n${Color_Off}"
docker image tag ${S1_REPO_AGENT}:${S1_AGENT_TAG_x86_64}  ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG_x86_64}
docker image tag ${S1_REPO_AGENT}:${S1_AGENT_TAG_aarch64} ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG_aarch64}

# helper
printf "\n${Yellow}INFO:  Tagging helper images in private repository ${PRIVATE_REPO_HELPER} \n\n${Color_Off}"
docker image tag ${S1_REPO_HELPER}:${S1_HELPER_TAG_x86_64}  ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG_x86_64}
docker image tag ${S1_REPO_HELPER}:${S1_HELPER_TAG_aarch64} ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG_aarch64}

################################################################################
# Push all images and manifest to private registry
################################################################################

# Push agent images
printf "\n${Yellow}INFO:  Pushing agent images to private repository ${PRIVATE_REPO_AGENT} \n\n${Color_Off}"
docker push ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG_x86_64}
docker push ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG_aarch64}

# Push helper images
printf "\n${Yellow}INFO:  Pushinbg helper images to private repository ${PRIVATE_REPO_HELPER} \n\n${Color_Off}"
docker push ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG_x86_64}
docker push ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG_aarch64}

# Create and push manifest for the agent images
printf "\n${Yellow}INFO:  Creating agent manifest in private repository ${PRIVATE_REPO_AGENT} \n\n${Color_Off}"
docker manifest create ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG} \
    --amend ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG_x86_64} \
    --amend ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG_aarch64}
docker manifest push ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG}

# Create and push manifest for the helper images
printf "\n${Yellow}INFO:  Creating helper manifest in private repository ${PRIVATE_REPO_HELPER} \n\n${Color_Off}"
docker manifest create ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG} \
    --amend ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG_x86_64} \
    --amend ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG_aarch64}
docker manifest push ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG}

################################################################################
# Validate manifest in private registry
################################################################################

# agent
printf "\n${Yellow}INFO:  Validating agent manifest in private repository ${PRIVATE_REPO_AGENT} \n\n${Color_Off}"
docker manifest inspect ${PRIVATE_REPO_AGENT}:${S1_AGENT_TAG}

# helper
printf "\n${Yellow}INFO:  Validating helper manifest in private repository ${PRIVATE_REPO_HELPER} \n\n${Color_Off}"
docker manifest inspect ${PRIVATE_REPO_HELPER}:${S1_HELPER_TAG}

printf "\n${Green}Finished! ${Color_Off}\n"
exit 0
