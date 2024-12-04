#!/bin/bash
##############################################################################################################
# Description:  Bash script to aid with automating S1 Kubernetes Agent install
# 
# Usage:  sudo ./s1-k8s-agent-install-repo.sh S1_REPOSITORY_USERNAME S1_REPOSITORY_PASSWORD S1_SITE_TOKEN S1_AGENT_TAG S1_AGENT_LOG_LEVEL K8S_TYPE
# 
# Version:  2024-12-04
#
# Reference:  https://community.sentinelone.com/s/article/000008772
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

# Example format of 's1.config' file for usage with this script
# S1_REPOSITORY_USERNAME=""
# S1_REPOSITORY_PASSWORD=""
# S1_SITE_TOKEN=""
# S1_AGENT_TAG="24.2.2-ga"
# S1_AGENT_LOG_LEVEL="info"
# K8S_TYPE="k8s"

# Check for s1.config file.  If it exists, source it.
if [ -f s1.config ]; then
    printf "\n${Yellow}INFO:  Found 's1.config' file in $(pwd).${Color_Off}\n\n"
    source s1.config
else
    printf "\n${Yellow}INFO:  No 's1.config' file found in $(pwd).${Color_Off}\n\n"
fi 

# Check if all 4 mandatory arguments were passed to the script
if [ $# -eq 4 ] || [ $# -eq 5 ]; then
    printf "\n${Yellow}INFO:  Found $# arguments that were passed to the script. \n\n${Color_Off}"
    S1_REPOSITORY_USERNAME=$1
    S1_REPOSITORY_PASSWORD=$2
    S1_SITE_TOKEN=$3
    S1_AGENT_TAG=$4
    S1_AGENT_LOG_LEVEL="${5:-info}"
    K8S_TYPE="${6:-k8s}"
fi

# Check if arguments have been passed at all.
if [ $# -eq 0 ]; then
    printf "\n${Yellow}INFO:  No input arguments were passed to the script. \n\n${Color_Off}"
    S1_AGENT_LOG_LEVEL="info"
    if [ -z ${K8S_TYPE} ]; then 
        K8S_TYPE="k8s"
    fi
fi

# If the 4 mandatory variables have not been sourced from the s1.config file, passed via cmdline 
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

if [ -z $S1_AGENT_TAG ];then
    echo ""
    read -p "Please enter the SentinelOne Agent Version to install (ie: 24.2.2-ga): " S1_AGENT_TAG
fi

# If K8S_TYPE is set to openshift, autopilot, or fargate, we set special variables that are used to dynamically add helm flags during install
case $K8S_TYPE in
  k8s)
  echo "standard k8s"
  ;;

  openshift)
  OPENSHIFT='true'
  echo "openshift"
  ;;

  autopilot)
  AUTOPILOT='true'
  echo "autopilot"
  ;;

  fargate)
  FARGATE='true'
  echo "fargate"
  ;;
esac

# We derive the helm release/chart version from the SentinelOne Agent version/tag + set the s1helper tag to be the same as the s1agent tag.
# This requires removing the [-ea|-ga] designator from the S1_AGENT_TAG
HELM_RELEASE_VERSION=$(echo $S1_AGENT_TAG | cut -d "-" -f1) # ie: 23.4.2
S1_HELPER_TAG=$S1_AGENT_TAG

# Get cluster name from the current context
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[].name}')
printf "\n${Purple}Cluster Name:  $CLUSTER_NAME\n${Color_Off}"

# The following variable values can be customized as you see fit (or can be left as is).
S1_PULL_SECRET_NAME=sentinelone-registry
HELM_RELEASE_NAME=sentinelone
S1_NAMESPACE=sentinelone
# Resource Limits and Requests for Agent
# GKE Autopilot may override these based on bursting availability in your clusters
# https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests
S1_AGENT_LIMITS_MEMORY='1945Mi'
S1_AGENT_LIMITS_CPU='900m'
S1_AGENT_REQUESTS_MEMORY='800Mi'
S1_AGENT_REQUESTS_CPU='500m'
# Resource Limits and Requests for Helper
S1_HELPER_LIMITS_MEMORY='1945Mi'
S1_HELPER_LIMITS_CPU='900m'
S1_HELPER_REQUESTS_MEMORY='100Mi'
S1_HELPER_REQUESTS_CPU='100m'
# Environment
S1_AGENT_HEAP_TRIMMING_ENABLE='true'
S1_PROXY=''
S1_DV_PROXY=''

# The following variables SHOULD NOT BE ALTERED
REPO_BASE=containers.sentinelone.net
REPO_HELPER=$REPO_BASE/cws-agent/s1helper
REPO_AGENT=$REPO_BASE/cws-agent/s1agent


################################################################################
# Sanity Check the execution environment 
################################################################################

# Check for prerequisite binaries
if ! command -v kubectl &> /dev/null ; then
    printf "\n${Red}Missing the 'kubectl' utility.  Please install this utility and try again.\n"
    printf "Reference:  https://kubernetes.io/docs/tasks/tools/install-kubectl/\n${Color_Off}"
    exit 1
fi

if ! command -v helm &> /dev/null ; then
    printf "\n${Red}Missing the 'helm' utility!  Please install this utility and try again.\n"
    printf "Reference:  https://helm.sh/docs/intro/install/\n${Color_Off}"
    exit 1
fi

# Check that we have a context established
if ! command -v kubectl get nodes  &> /dev/null ; then
    printf "\n${Red}Unable to issue 'kubectl get nodes' command.  Please ensure that a valid context has been established with the target cluster.\n"
    printf "ie: kubectl config get-context\n"
    printf "kubectl config use-context CONTEXT\n${Color_Off}"
    exit 1
fi



# # Check if the minimum number of arguments have been passed
# if [ $# -lt 4 ]; then
#     printf "\n${Red}ERROR:  Expecting at least 4 arguments to be passed. \n${Color_Off}"
#     printf "Example usage: \n"
#     printf "ie:${Green}  $0 \$S1_SITE_TOKEN \$S1_REPOSITORY_USERNAME \$S1_REPOSITORY_PASSWORD 23.4.2-ga debug \n${Color_Off}"
#     printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
#     printf "    ${Blue}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n\n"
#     printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
#     printf "    ${Blue}https://community.sentinelone.com/s/article/000008771 ${Color_Off} \n\n"
#     exit 1
# fi


################################################################################
# Sanity Check the variable inputs
################################################################################

# Check if the value of S1_SITE_TOKEN is in the right format
if ! echo $S1_SITE_TOKEN | base64 -d | grep sentinelone.net &> /dev/null ; then
    printf "\n${Red}ERROR:  Site Token does not decode correctly.  Please ensure that you've passed a valid Site Token as the first argument to the script. \n${Color_Off}"
    printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Blue}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n\n"
    exit 1
fi

# Check if the value of S1_REPOSITORY_USERNAME is in the right format
if ! echo $S1_REPOSITORY_USERNAME | base64 -d | egrep '^[0-9]+\:(aws|gcp)\:[a-zA-Z0-9-]+\:[a-zA-Z0-9-]+$' &> /dev/null ; then
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
if ! echo $S1_AGENT_TAG | egrep '^[0-9][0-9].[0-9].[0-9]-[ge]a$' &> /dev/null ; then
    printf "\n${Red}ERROR:  The value passed for S1_AGENT_TAG is not in the correct format.  Examples of valid values are: 24.2.2-ga,  23.4.2-ga, and 24.1.1-ea \n\n${Color_Off}"
    exit 1
fi

# Check if the value of S1_AGENT_LOG_LEVEL is trace, debug, info (default), warning, error or fatal.  If not, it's invalid.
if ! echo $S1_AGENT_LOG_LEVEL | egrep '^(trace|debug|info|warning|error|fatal)$'  &> /dev/null ; then
    printf "\n${Red}ERROR:  The value passed for S1_AGENT_LOG_LEVEL does not contain a valid valude.  Valid values are trace, debug, info (default), warning, error or fatal. \n\n${Color_Off}"
    exit 1
fi


################################################################################
# Create the 'sentinelone' namespace and pull secret
################################################################################

# Create namespace for S1 resources (if it doesn't already exist)
printf "\n${Purple}Creating namespace...\n${Color_Off}"
if ! kubectl get ns ${S1_NAMESPACE} &> /dev/null ; then
    kubectl create namespace ${S1_NAMESPACE}
fi

# Create Kubernetes secret to house the credentials used to access the container registry repos
printf "\n${Purple}Creating K8s secret ${S1_PULL_SECRET_NAME}...\n${Color_Off}"
if ! kubectl get secret ${S1_PULL_SECRET_NAME} -n ${S1_NAMESPACE} &> /dev/null ; then
    printf "\n${Purple}Creating secret for S1 image download in K8s...\n${Color_Off}"
    kubectl create secret docker-registry -n ${S1_NAMESPACE} ${S1_PULL_SECRET_NAME} \
        --docker-username="${S1_REPOSITORY_USERNAME}" \
        --docker-server="${REPO_BASE}" \
        --docker-password="${S1_REPOSITORY_PASSWORD}"
fi


################################################################################
# Add the Helm repo and install the helm chart
################################################################################

# Add the SentinelOne helm repo
printf "\n${Purple}Adding SentinelOne Helm Repo...\n${Color_Off}"
if ! helm repo list | grep sentinelone &> /dev/null ; then
    helm repo add sentinelone https://charts.sentinelone.com
fi

# Ensure we have the latest charts
printf "\n${Purple}Running helm repo update...\n${Color_Off}"
helm repo update

# Deploy S1 agent!  Upgrade it if it already exists
printf "\n${Purple}Deploying Helm Chart...\n${Color_Off}"
helm upgrade --install ${HELM_RELEASE_NAME} --namespace=${S1_NAMESPACE} --version ${HELM_RELEASE_VERSION} \
    --set secrets.imagePullSecret=${S1_PULL_SECRET_NAME} \
    --set secrets.site_key.value=${S1_SITE_TOKEN} \
    --set configuration.repositories.agent=${REPO_AGENT} \
    --set configuration.tag.agent=${S1_AGENT_TAG} \
    --set configuration.repositories.helper=${REPO_HELPER} \
    --set configuration.tag.helper=${S1_HELPER_TAG} \
    --set configuration.cluster.name=$CLUSTER_NAME \
    --set helper.nodeSelector."kubernetes\\.io/os"=linux \
    --set agent.nodeSelector."kubernetes\\.io/os"=linux \
    --set helper.resources.limits.memory=${S1_HELPER_LIMITS_MEMORY} \
    --set helper.resources.limits.cpu=${S1_HELPER_LIMITS_CPU} \
    --set helper.resources.requests.memory=${S1_HELPER_REQUESTS_MEMORY} \
    --set helper.resources.requests.cpu=${S1_HELPER_REQUESTS_CPU} \
    --set agent.resources.limits.memory=${S1_AGENT_LIMITS_MEMORY} \
    --set agent.resources.limits.cpu=${S1_AGENT_LIMITS_CPU} \
    --set agent.resources.requests.memory=${S1_AGENT_REQUESTS_MEMORY} \
    --set agent.resources.requests.cpu=${S1_AGENT_REQUESTS_CPU} \
    --set configuration.env.agent.heap_trimming_enable=${S1_AGENT_HEAP_TRIMMING_ENABLE} \
    --set configuration.env.agent.log_level=${S1_AGENT_LOG_LEVEL} \
    --set configuration.proxy=${S1_PROXY} \
    --set configuration.dv_proxy=${S1_DV_PROXY} \
    ${OPENSHIFT:+--set configuration.platform.type=openshift} \
    ${AUTOPILOT:+--set configuration.platform.gke.autopilot=true} \
    ${FARGATE:+--set configuration.env.injection.enabled=true --set helper.labels.Application=sentinelone --set configuration.env.agent.pod_uid=0 --set configuration.env.agent.pod_gid=0} \
    sentinelone/s1-agent


################################################################################
# Run a basic status check to show that the agent and helper have deployed
################################################################################

# Check the status of the pods
printf "\n${Purple}Running: kubectl wait --for=condition=ready --timeout=60s pod -n $S1_NAMESPACE -l app=s1-agent\n${Color_Off}"
printf "\n${Purple}This should take less than 60 seconds...\n${Color_Off}"
kubectl wait --for=condition=ready pod -n $S1_NAMESPACE -l app=s1-agent
