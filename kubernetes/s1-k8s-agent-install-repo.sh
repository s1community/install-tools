#!/bin/bash
##############################################################################################################
# Description:  Bash script to aid with automating SentinelOne CWS Container agent install
# 
# Usage:  sudo ./s1-k8s-agent-install-repo.sh [USERNAME] [PASSWORD] [SITE_TOKEN] [AGENT_TAG] [LOG_LEVEL] [K8S_TYPE] [ADMISSION_CONTROLLER] [CLUSTER_NAME] [CLUSTER_UID]
#
# Arguments may be supplied positionally (in the order below), via an 's1.config' file in the
# current directory, or as exported environment variables.  If a required value is not found by
# any of these methods, the script will prompt for it interactively.
#
# RECOMMENDED:  Use an 's1.config' file (copy 's1.config.example' to 's1.config') for the sensitive
# values (registry credentials and site token).  See the SECURITY note below.
#
#   #  Variable                  Req?  Description / valid values                              Default
#   -  ------------------------  ----  -------------------------------------------------------  -------
#   1  S1_REPOSITORY_USERNAME    yes   Base64 registry username (see header link)               -
#   2  S1_REPOSITORY_PASSWORD    yes   Base64 registry password (see header link)               -
#   3  S1_SITE_TOKEN             yes   Base64 site token (see header link)                      -
#   4  S1_AGENT_TAG              yes   X.Y.Z-(ga|ea), e.g. 26.1.1-ga (see header link)          -
#   5  S1_AGENT_LOG_LEVEL        no    trace|debug|info|warning|error|fatal                     info
#   6  K8S_TYPE                  no    k8s|openshift|autopilot|fargate|eksauto                  k8s
#   7  S1_ADMISSION_CONTROLLER   no    true|false (enable validating admission controller)      true
#   8  CLUSTER_NAME              no*   Cluster name EXACTLY as it appears in AWS/Azure/GCP       (prompt)
#   9  CLUSTER_UID               no*   Cloud Cluster UID for managed clusters (see below)        ""
#
#  * For managed EKS/AKS/GKE clusters deployed manually, set CLUSTER_NAME and CLUSTER_UID so the
#    agent's inventory is consolidated deterministically with the cloud (CNS) inventory surface.
#    CLUSTER_UID is the cloud-specific cluster identifier:
#       AWS EKS:    cluster ARN          aws eks describe-cluster --name <name> --region <region> --query 'cluster.arn' --output text
#       Azure AKS:  Resource ID          az aks show --name <name> --resource-group <rg> --query 'id' --output tsv
#       Google GKE: cluster ID           gcloud container clusters describe <name> --region <region> --format='value(id)'
#    For self-managed (non-cloud) clusters, leave CLUSTER_UID empty -- the scanner/helper generates it.
#
#
# Create Repo Username/Password:  https://community.sentinelone.com/s/article/000011517
#   (see the "Manual deployment for Container Agent" section)
#
# Retrieve a Site Token:  https://community.sentinelone.com/s/article/000004904
#   ("Retrieving a Site or Group Token")
#
# Find the Latest Agent Version:  https://community.sentinelone.com/s/article/000004966
#   ("Latest Information" - use the "Image index tag" value for "Container Agent"
#    in the "Latest Agent GA and SP releases" table)
#
# Supported Kubernetes Types & Resource Sizing:  https://community.sentinelone.com/s/article/000008829
#   ("Requirements and recommendations for Container Agent" - covers supported K8S_TYPE values
#    and guidance for the agent/helper resource requests and limits set below)
#
# All Helm Chart Options:  https://community.sentinelone.com/s/article/000008816
#   ("Container Agent Helm chart options" - full reference for the --set flags used below)
#
# Version:  2026.06.21
#
# NOTE: Please be aware that there is a 100 pulls/hour rate limit for the SentinelOne repository!!
#
# SECURITY: Passing the registry credentials and site token as command-line arguments records them
#       in your shell history (e.g. ~/.bash_history) and exposes them to other local users via the
#       process list (ps).  Prefer an 's1.config' file, or run with no arguments to be prompted
#       interactively (prompt input is not echoed or stored).
#
# NOTE: Setting S1_ADMISSION_CONTROLLER=true only deploys the SentinelOne validating admission
#       controller webhook.  To actually monitor and/or enforce, you must also enable an
#       Admission Controller Policy in the SentinelOne management console:
#       https://community.sentinelone.com/s/article/000011916 ("Configuring Admission Controller policies")
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
# S1_REPOSITORY_USERNAME=""           # Base64 registry username (required; see header link)
# S1_REPOSITORY_PASSWORD=""           # Base64 registry password (required; see header link)
# S1_SITE_TOKEN=""                    # Base64 site token (required; see header link)
# S1_AGENT_TAG="26.1.1-ga"            # Agent version, X.Y.Z-(ga|ea) (required; see header link)
# S1_AGENT_LOG_LEVEL="info"           # trace|debug|info|warning|error|fatal  (default: info)
# K8S_TYPE="k8s"                      # k8s|openshift|autopilot|fargate|eksauto  (default: k8s; see header link)
# S1_ADMISSION_CONTROLLER="true"      # true|false  (default: true)
# CLUSTER_NAME=""                     # Cluster name EXACTLY as it appears in AWS/Azure/GCP (prompted if empty)
# CLUSTER_UID=""                      # Cloud Cluster UID for managed clusters; leave empty for self-managed (see header)

# Check for s1.config file.  If it exists, source it.
if [ -f s1.config ]; then
    printf "\n${Yellow}INFO:  Found 's1.config' file in $(pwd).${Color_Off}\n\n"
    source s1.config
else
    printf "\n${Yellow}INFO:  No 's1.config' file found in $(pwd).${Color_Off}\n\n"
fi 

# Check if mandatory arguments were passed to the script
if [ $# -ge 4 ]; then
    printf "\n${Yellow}INFO:  Found $# arguments that were passed to the script. \n\n${Color_Off}"
    S1_REPOSITORY_USERNAME=$1
    S1_REPOSITORY_PASSWORD=$2
    S1_SITE_TOKEN=$3
    S1_AGENT_TAG=$4
    S1_AGENT_LOG_LEVEL="${5:-info}"
    K8S_TYPE="${6:-k8s}"
    S1_ADMISSION_CONTROLLER="${7:-true}"
    CLUSTER_NAME="${8:-$CLUSTER_NAME}"
    CLUSTER_UID="${9:-$CLUSTER_UID}"
fi

# Check if arguments have been passed at all.
if [ $# -eq 0 ]; then
    printf "\n${Yellow}INFO:  No input arguments were passed to the script. \n\n${Color_Off}"
fi

# Apply defaults for the optional variables so they always have a value, regardless of how the
#   script was invoked (positional arg, s1.config, exported env var, or not set at all).  This
#   also covers the case where 1-3 positional args are passed (neither branch above runs).
S1_AGENT_LOG_LEVEL="${S1_AGENT_LOG_LEVEL:-info}"
K8S_TYPE="${K8S_TYPE:-k8s}"
S1_ADMISSION_CONTROLLER="${S1_ADMISSION_CONTROLLER:-true}"

# If the 4 mandatory variables have not been sourced from the s1.config file, passed via cmdline 
#   arguments or read from exported variables of the parent shell, we'll prompt the user for them.
if [ -z "$S1_REPOSITORY_USERNAME" ];then
    echo ""
    read -rp "Please enter your SentinelOne Repo Username: " S1_REPOSITORY_USERNAME
fi

if [ -z "$S1_REPOSITORY_PASSWORD" ];then
    echo ""
    read -rsp "Please enter your SentinelOne Repo Password: " S1_REPOSITORY_PASSWORD
    echo ""
fi

if [ -z "$S1_SITE_TOKEN" ];then
    echo ""
    read -rsp "Please enter your SentinelOne Site Token: " S1_SITE_TOKEN
    echo ""
fi

if [ -z "$S1_AGENT_TAG" ];then
    echo ""
    read -rp "Please enter the SentinelOne Agent Version to install (ie: 26.1.1-ga): " S1_AGENT_TAG
fi

# If K8S_TYPE is set to openshift, autopilot, fargate, or eksauto, we set special variables that are used to dynamically add helm flags during install
case $K8S_TYPE in
  k8s)
  printf "\n${Yellow}INFO:  Detected K8S_TYPE='k8s' (standard Kubernetes). \n\n${Color_Off}"
  ;;

  openshift)
  OPENSHIFT='true'
  printf "\n${Yellow}INFO:  Detected K8S_TYPE='openshift' (Red Hat OpenShift). \n\n${Color_Off}"
  ;;

  autopilot)
  # GKE Autopilot deployment guide: https://community.sentinelone.com/s/article/000011984
  #   ("Deploying the Container Agent to GKE Autopilot")
  AUTOPILOT='true'
  printf "\n${Yellow}INFO:  Detected K8S_TYPE='autopilot' (GKE Autopilot). \n\n${Color_Off}"
  ;;

  fargate)
  # EKS Fargate deployment guide: https://community.sentinelone.com/s/article/000012505
  #   ("Deploying the Container Agent on Kubernetes with Fargate")
  FARGATE='true'
  printf "\n${Yellow}INFO:  Detected K8S_TYPE='fargate' (EKS Fargate). \n\n${Color_Off}"
  ;;

  eksauto)
  EKSAUTO='true'
  printf "\n${Yellow}INFO:  Detected K8S_TYPE='eksauto' (EKS Auto Mode). \n\n${Color_Off}"
  ;;

  *)
  printf "\n${Red}ERROR:  Invalid K8S_TYPE '${K8S_TYPE}'.  Valid values are: k8s, openshift, autopilot, fargate, eksauto. \n${Color_Off}"
  printf "\nFor details on ${Purple}supported Kubernetes types${Color_Off}, please see the following KB article:\n"
  printf "    ${Blue}https://community.sentinelone.com/s/article/000008829 ${Color_Off} \n"
  printf "    ${Cyan}(\"Requirements and recommendations for Container Agent\")${Color_Off} \n\n"
  exit 1
  ;;
esac

# We derive the helm release/chart version from the SentinelOne Agent version/tag + set the s1helper tag to be the same as the s1agent tag.
# This requires removing the [-ea|-ga] designator from the S1_AGENT_TAG
HELM_RELEASE_VERSION=$(echo $S1_AGENT_TAG | cut -d "-" -f1) # ie: 26.1.1
S1_HELPER_TAG=$S1_AGENT_TAG

# NOTE: Cluster identity (CLUSTER_NAME / CLUSTER_UID) is resolved later, after the kubectl context
#       sanity checks, so we can detect the cloud provider and prompt with provider-specific guidance.

# The following variable values can be customized as you see fit (or can be left as is).
# For guidance on sizing the agent/helper resource requests and limits below, see:
#   https://community.sentinelone.com/s/article/000008829 ("Requirements and recommendations for Container Agent")
S1_PULL_SECRET_NAME=sentinelone-registry
HELM_RELEASE_NAME=sentinelone
S1_NAMESPACE=sentinelone
S1_ALLOWLIST=s1-agent-allowlist-synchronizer.yaml
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

# The following variables SHOULD NOT BE ALTERED unless you need to use the GovCloud Repo URL of 'containers.na2.s1gov.net'.
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
if ! kubectl get nodes  &> /dev/null ; then
    printf "\n${Red}Unable to issue 'kubectl get nodes' command.  Please ensure that a valid context has been established with the target cluster.\n"
    printf "ie: kubectl config get-context\n"
    printf "kubectl config use-context CONTEXT\n${Color_Off}"
    exit 1
fi

################################################################################
# Resolve cluster identity (CLUSTER_NAME / CLUSTER_UID) for inventory consolidation
################################################################################

# Detect the cloud provider from the first node's providerID.  This needs no extra credentials and
#   is far more reliable than the kubectl context name.
#   providerID prefixes:  aws:///...  azure:///...  gce://...   (anything else => self-managed)
NODE_PROVIDER_ID=$(kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null)
case "$NODE_PROVIDER_ID" in
    aws:*)   CLOUD_PROVIDER="aws"   ;;
    azure:*) CLOUD_PROVIDER="azure" ;;
    gce:*)   CLOUD_PROVIDER="gcp"   ;;
    *)       CLOUD_PROVIDER="none"  ;;
esac

# Best-effort: sniff a SUGGESTED cluster name from well-known node labels.  These are NOT authoritative
#   (labels are provider-specific and frequently hold an adjacent value rather than the cloud cluster
#   name), so we only offer the result as a pre-filled default the user can accept or override -- it is
#   never trusted blindly.
SUGGESTED_CLUSTER_NAME=""
case "$CLOUD_PROVIDER" in
    aws)
        # eksctl-built clusters stamp this label; plain EKS managed node groups usually do not.
        SUGGESTED_CLUSTER_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.labels.alpha\.eksctl\.io/cluster-name}' 2>/dev/null)
        ;;
    azure)
        # AKS nodes carry kubernetes.azure.com/cluster = MC_<resourceGroup>_<clusterName>_<region>.
        #   Parse the cluster name from the middle (best-effort; ambiguous if the RG/name contain '_').
        AKS_NODE_RG=$(kubectl get nodes -o jsonpath='{.items[0].metadata.labels.kubernetes\.azure\.com/cluster}' 2>/dev/null)
        if [ -n "$AKS_NODE_RG" ]; then
            SUGGESTED_CLUSTER_NAME=$(echo "$AKS_NODE_RG" | sed -E 's/^MC_.+_([^_]+)_[^_]+$/\1/')
            # If the pattern did not match, sed echoes the input unchanged -- treat that as "no suggestion".
            [ "$SUGGESTED_CLUSTER_NAME" = "$AKS_NODE_RG" ] && SUGGESTED_CLUSTER_NAME=""
        fi
        ;;
    gcp)
        # GKE exposes no cluster-name node label; the name lives in the GCP metadata server (unreachable here).
        :
        ;;
esac

# Cluster name MUST match the cluster's name EXACTLY as it appears in AWS/Azure/GCP.  We intentionally
#   do NOT derive it from the kubectl context, because the context name rarely matches the cloud name.
if [ -z "$CLUSTER_NAME" ]; then
    echo ""
    printf "${Yellow}The Cluster Name should match the cluster's name EXACTLY as it appears in AWS, Azure, or GCP.${Color_Off}\n"
    if [ -n "$SUGGESTED_CLUSTER_NAME" ]; then
        printf "${Yellow}A possible name was detected from node labels -- VERIFY it is correct before accepting.${Color_Off}\n"
        read -rp "Please enter the Cluster Name [${SUGGESTED_CLUSTER_NAME}]: " CLUSTER_NAME
        CLUSTER_NAME="${CLUSTER_NAME:-$SUGGESTED_CLUSTER_NAME}"
    else
        read -rp "Please enter the Cluster Name: " CLUSTER_NAME
    fi
fi
printf "\n${Purple}Cluster Name:  ${CLUSTER_NAME}\n${Color_Off}"

# Cluster UID enables deterministic consolidation of inventory between the agent and the cloud (CNS)
#   surface.  Set it for MANAGED clusters deployed manually; leave it empty for self-managed clusters
#   (the scanner/helper generates the ID).  If we detect a managed cluster but no UID was supplied,
#   show the provider-specific command and prompt for it.
if [ -z "$CLUSTER_UID" ] && [ "$CLOUD_PROVIDER" != "none" ]; then
    echo ""
    printf "${Yellow}Detected a managed '${CLOUD_PROVIDER}' cluster, but no Cluster UID was provided.${Color_Off}\n"
    printf "${Yellow}A Cluster UID lets SentinelOne deterministically consolidate the agent's inventory with the cloud inventory surface.${Color_Off}\n\n"
    case "$CLOUD_PROVIDER" in
        aws)
            printf "  For AWS EKS, the Cluster UID is the ARN of the cluster:\n"
            printf "    ${Cyan}aws eks describe-cluster --name ${CLUSTER_NAME} --region <region> --query 'cluster.arn' --output text${Color_Off}\n\n"
            ;;
        azure)
            printf "  For Azure AKS, the Cluster UID is the Resource ID of the cluster:\n"
            printf "    ${Cyan}az aks show --name ${CLUSTER_NAME} --resource-group <resource-group> --query 'id' --output tsv${Color_Off}\n\n"
            ;;
        gcp)
            printf "  For Google GKE, the Cluster UID is the cluster ID:\n"
            printf "    ${Cyan}gcloud container clusters describe ${CLUSTER_NAME} --region <region> --format='value(id)'${Color_Off}\n\n"
            ;;
    esac
    read -rp "Please enter the Cluster UID (or press Enter to skip): " CLUSTER_UID
fi

if [ -n "$CLUSTER_UID" ]; then
    printf "${Purple}Cluster UID:   ${CLUSTER_UID}\n${Color_Off}"
fi

################################################################################
# Sanity Check the variable inputs
################################################################################

# Check if the value of S1_SITE_TOKEN is in the right format
if ! echo "$S1_SITE_TOKEN" | base64 -d | grep sentinelone.net &> /dev/null ; then
    printf "\n${Red}ERROR:  Site Token does not decode correctly.  Please ensure that you've provided a valid Site Token (S1_SITE_TOKEN). \n${Color_Off}"
    printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Blue}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n"
    printf "    ${Cyan}(\"Retrieving a Site or Group Token\")${Color_Off} \n\n"
    exit 1
fi

# Check if the value of S1_REPOSITORY_USERNAME is in the right format
if ! echo "$S1_REPOSITORY_USERNAME" | base64 -d | grep -E '^[0-9]+\:(aws|gcp)\:[a-zA-Z0-9-]+\:[a-zA-Z0-9-]+$' &> /dev/null ; then
    printf "\n${Red}ERROR:  The value provided for S1_REPOSITORY_USERNAME does not decode correctly.  Please ensure that you've provided a valid Registry Username (S1_REPOSITORY_USERNAME). \n${Color_Off}"
    printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Blue}https://community.sentinelone.com/s/article/000011517 ${Color_Off} \n"
    printf "    ${Cyan}(see the \"Manual deployment for Container Agent\" section)${Color_Off} \n\n"
    exit 1
fi

# Check if the value of S1_REPOSITORY_PASSWORD is in the right format
if ! [ ${#S1_REPOSITORY_PASSWORD} -gt 160 ]; then
    printf "\n${Red}ERROR:  The value provided for S1_REPOSITORY_PASSWORD did not pass a basic length test (longer than 160 characters).  Please ensure that you've provided a valid Registry Password (S1_REPOSITORY_PASSWORD). \n${Color_Off}"
    printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Blue}https://community.sentinelone.com/s/article/000011517 ${Color_Off} \n"
    printf "    ${Cyan}(see the \"Manual deployment for Container Agent\" section)${Color_Off} \n\n"
    exit 1
fi

# Check if the value of S1_AGENT_TAG is in the right format
if ! echo "$S1_AGENT_TAG" | grep -E '^[0-9]{2}\.[0-9]\.[0-9]+-(ga|ea)$' &> /dev/null ; then
    printf "\n${Red}ERROR:  The value provided for S1_AGENT_TAG is not in the correct format.  Examples of valid values are: 26.1.1-ga, 25.4.2-ga,25.3.2-ga \n${Color_Off}"
    printf "\nFor the ${Purple}latest available Agent versions${Color_Off}, please see the following KB article:\n"
    printf "    ${Blue}https://community.sentinelone.com/s/article/000004966 ${Color_Off} \n"
    printf "    ${Cyan}(\"Latest Information\" - \"Image index tag\" for \"Container Agent\" in the \"Latest Agent GA and SP releases\" table)${Color_Off} \n\n"
    exit 1
fi

# Check if the value of S1_AGENT_LOG_LEVEL is trace, debug, info (default), warning, error or fatal.  If not, it's invalid.
if ! echo "$S1_AGENT_LOG_LEVEL" | grep -E '^(trace|debug|info|warning|error|fatal)$' &> /dev/null ; then
    printf "\n${Red}ERROR:  The value provided for S1_AGENT_LOG_LEVEL does not contain a valid value.  Valid values are trace, debug, info (default), warning, error or fatal. \n\n${Color_Off}"
    exit 1
fi

# Check if the value of S1_ADMISSION_CONTROLLER is either true (default) or false.  If not, it's invalid.
if ! echo "$S1_ADMISSION_CONTROLLER" | grep -E '^(true|false)$' &> /dev/null ; then
    printf "\n${Red}ERROR:  The value provided for S1_ADMISSION_CONTROLLER does not contain a valid value.  Valid values are true (default) or false. \n\n${Color_Off}"
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

# Create the image pull secret that holds the credentials used to authenticate to the SentinelOne container registry
printf "\n${Purple}Configuring image pull secret '${S1_PULL_SECRET_NAME}' for the SentinelOne container registry...\n${Color_Off}"
if ! kubectl get secret ${S1_PULL_SECRET_NAME} -n ${S1_NAMESPACE} &> /dev/null ; then
    printf "\n${Purple}Creating image pull secret '${S1_PULL_SECRET_NAME}'...\n${Color_Off}"
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

# Create and apply AllowlistSynchronizer for GKE Autopilot
# https://community.sentinelone.com/s/article/000011984
if [ "${AUTOPILOT}" = "true" ]; then 
    printf "\n${Purple}Deploying AllowlistSynchronizer for GKE Autopilot...\n${Color_Off}"
    cat << 'EOF' > ${S1_ALLOWLIST}
apiVersion: auto.gke.io/v1
kind: AllowlistSynchronizer
metadata:
  name: s1-agent-allowlist-synchronizer
spec:
  allowlistPaths:
    - SentinelOne/s1-agent/*
EOF
    kubectl apply -f ${S1_ALLOWLIST}
fi

# Re-home guard:  if this release already exists with a DIFFERENT Cluster UID, warn before changing it.
#   The most likely cause is reusing the same script or 's1.config' against a SECOND cluster -- every
#   cluster must have its own unique Cluster UID.  Changing the UID on an existing release re-homes the
#   cluster's identity in SentinelOne and can orphan or hide findings tied to the previous cluster asset.
EXISTING_CLUSTER_UID=$(helm get values ${HELM_RELEASE_NAME} --namespace ${S1_NAMESPACE} -o json 2>/dev/null \
    | sed -n 's/.*"uid": *"\([^"]*\)".*/\1/p')
if [ -n "$EXISTING_CLUSTER_UID" ] && [ -n "$CLUSTER_UID" ] && [ "$EXISTING_CLUSTER_UID" != "$CLUSTER_UID" ]; then
    printf "\n${Red}WARNING:  The existing '${HELM_RELEASE_NAME}' release in namespace '${S1_NAMESPACE}' already has a Cluster UID:\n"
    printf "            ${EXISTING_CLUSTER_UID}\n"
    printf "          which DIFFERS from the value you are about to apply:\n"
    printf "            ${CLUSTER_UID}\n\n"
    printf "          This usually means the same script or 's1.config' is being reused against a DIFFERENT\n"
    printf "          cluster -- each cluster must have its own unique Cluster UID.  If so, you are likely\n"
    printf "          running against the wrong context; check 'kubectl config current-context'.\n\n"
    printf "          Proceeding will re-home this cluster's identity in SentinelOne and may orphan or hide\n"
    printf "          findings tied to the previous cluster asset.${Color_Off}\n\n"
    read -rp "Type 'yes' to proceed with the new Cluster UID: " CONFIRM_UID
    if [ "$CONFIRM_UID" != "yes" ]; then
        printf "\n${Red}Aborting at user request.\n${Color_Off}"
        exit 1
    fi
fi

# Deploy S1 agent!  Upgrade it if it already exists
# For the full list of available Helm chart options/values, see:
#   https://community.sentinelone.com/s/article/000008816 ("Container Agent Helm chart options")
printf "\n${Purple}Deploying Helm Chart...\n${Color_Off}"
helm upgrade --install ${HELM_RELEASE_NAME} --namespace=${S1_NAMESPACE} --version ${HELM_RELEASE_VERSION} \
    --set secrets.imagePullSecret=${S1_PULL_SECRET_NAME} \
    --set secrets.site_key.value=${S1_SITE_TOKEN} \
    --set configuration.repositories.agent=${REPO_AGENT} \
    --set configuration.tag.agent=${S1_AGENT_TAG} \
    --set configuration.repositories.helper=${REPO_HELPER} \
    --set configuration.tag.helper=${S1_HELPER_TAG} \
    --set configuration.cluster.name=$CLUSTER_NAME \
    ${CLUSTER_UID:+--set configuration.cluster.uid=$CLUSTER_UID} \
    --set helper.nodeSelector."kubernetes\\.io/os"=linux \
    --set agent.nodeSelector."kubernetes\\.io/os"=linux \
    --set configuration.env.admission_controllers.validating.enabled=${S1_ADMISSION_CONTROLLER} \
    --set configuration.env.helper.inventory_enabled=true \
    --set configuration.env.helper.communicator_enabled=true \
    --set configuration.inventory_only=false \
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
    ${S1_PROXY:+--set configuration.proxy=${S1_PROXY}} \
    ${S1_DV_PROXY:+--set configuration.dv_proxy=${S1_DV_PROXY}} \
    ${OPENSHIFT:+--set configuration.platform.type=openshift} \
    ${AUTOPILOT:+--set configuration.platform.gke.autopilot=true} \
    ${FARGATE:+--set configuration.env.injection.enabled=true --set helper.labels.Application=sentinelone --set configuration.env.agent.pod_uid=0 --set configuration.env.agent.pod_gid=0} \
    ${EKSAUTO:+--set configuration.platform.type=bottlerocket} \
    sentinelone/s1-agent


################################################################################
# Run a basic status check to show that the agent and helper have deployed
################################################################################

# Check the status of the pods
printf "\n${Purple}Running: kubectl wait --for=condition=ready --timeout=60s pod -n $S1_NAMESPACE -l app=s1-agent\n${Color_Off}"
printf "\n${Purple}This should take less than 60 seconds in most cases...\n${Color_Off}"
kubectl wait --for=condition=ready --timeout=60s pod -n $S1_NAMESPACE -l app=s1-agent
