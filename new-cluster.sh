#!/usr/bin/env bash

PROJECTS=()
PROVIDER_NAME=""
PROJECT_NAME=""
CLUSTERS=()
TASK=""

# function check_os() {
#   if [[ "$OSTYPE" == "linux-gnu" ]]; then
#         # ...
#   elif [[ "$OSTYPE" == "darwin"* ]]; then
#         # Mac OSX
#   fi
# }

# function check_prereq() {
#   if hash gcloud 2>/dev/null; then
#         gdate "$@"
#     else
#         date "$@"
#   fi
# }

# function instal_prereq() {}

function welcome_user() {
  PS3="Are you here to Create a new cluster? " # or to Migrate a cluster ? "
  options=("Yes" "No")

  select opt in "${options[@]}"
  do
    case $opt in
        "Yes")
            TASK=0
            break
            ;;
        "No")
            TASK=1
            echo "Well I didn't want to create one any way!"
            exit 0;
            ;;
    esac
  done
}

function check_provider() {
  PS3="Select Cloud Provider: "
  options=("GKE" "AKS")

  select opt in "${options[@]}"
  do
    case $opt in
        "GKE")
            PROVIDER_NAME=gke
            break
            ;;
        "AKS")
            PROVIDER_NAME=aks
            echo "Currently the script only supports [GKE]."
            exit 0;
            ;;
    esac
  done
}

function check_projects(){
  GoogleConfig=$HOME/.config/gcloud/configurations/config_default
  if [ -f "$GoogleConfig" ]; then
    PS3="Select Cloud Project: "
    for row in $(gcloud projects list --format="json" | jq -r '.[].name | @base64'); do
      _jq() {
        echo ${row} | base64 --decode
      }
      PROJECTS+=("$(_jq)")
    done
    select opt in "${PROJECTS[@]}"
    do
      PROJECT_NAME=$opt
      break
    done
  else # GoogleConfig is not present, enter project name manually.
    while [[ -z "$PROJECT_NAME" ]]; do
      if [ ${#PROJECTS[@]} -eq 0 ]; then
        read -rp "What is the name of your project/subscription? " PROJECT_NAME
      else
        read -rp "Select project number: " PROJECT_NUM
        PROJECT_NAME=${PROJECTS[$PROJECT_NUM]}
        echo $PROJECT_NAME
      fi
    done
  fi
}

function check_clusters() {
  gcloud config set project $PROJECT_NAME > /dev/null 2>&1
  echo $'\e[1;33m'Existing Clusters:$'\e[0m'
  for cluster in $(gcloud container clusters list --format="json" | jq -r '.[].name'); do
    printf "\t * $cluster\n"
    CLUSTERS+=$cluster
  done
}

function check_cluster_locations(){
  GoogleConfig=$HOME/.config/gcloud/configurations/config_default
  if [ -f "$GoogleConfig" ]; then
    PS3="Select Cluster Location: "
    for row in $(gcloud compute regions list --format="json" | jq -r '.[].name | @base64'); do
      _jq() {
        echo ${row} | base64 --decode
      }
      LOCATIONS+=("$(_jq)")
    done
    select opt in "${LOCATIONS[@]}"
    do
      CLUSTER_LOCATION=$opt
      break
    done
  else
    while [[ -z "$CLUSTER_LOCATION" ]]; do
      if [ ${#LOCATIONS[@]} -eq 0 ]; then
        read -rp "What is the name of your project/subscription? " CLUSTER_LOCATION
      else
        read -rp "Select project number: " LOCATION_NUM
        CLUSTER_LOCATION=${LOCATIONS[$LOCATION_NUM]}
        echo $CLUSTER_LOCATION
      fi
    done
  fi
}

function check_node_locations(){
  GoogleConfig=$HOME/.config/gcloud/configurations/config_default
  if [ -f "$GoogleConfig" ]; then
    PS3="Select Node Pool Location: "
    for row in $(gcloud compute zones list --format="json" | jq -r ".[] | select(.region|test(\"$CLUSTER_LOCATION\")) | .name | @base64"); do
      _jq() {
        echo ${row} | base64 --decode
      }
      NODE_LOCATIONS+=("$(_jq)")
    done
    select opt in "${NODE_LOCATIONS[@]}"
    do
      NODE_LOCATION=$opt
      break
    done
  else
    while [[ -z "$NODE_LOCATION" ]]; do
      if [ ${#NODE_LOCATIONS[@]} -eq 0 ]; then
        read -rp "What is the name of your project/subscription? " NODE_LOCATION
      else
        read -rp "Select project number: " NODE_NUM
        NODE_LOCATION=${NODE_LOCATIONS[$NODE_NUM]}
        echo "$NODE_LOCATION"
      fi
    done
  fi
}

function create_cluster() {

  DEFAULT_CLUSTER_FOLDER="$(dirname "$0")/clusters/$PROVIDER_NAME/example_project/example_cluster"

  while [[ -z "$READY" ]]; do
    read -rp "What is the name of your cluster supposed to be? " CLUSTER_NAME
    if [[ " ${CLUSTERS[@]} " =~ "$CLUSTER_NAME" ]]; then
      echo $'\e[1;31m'Cluster with that name already exists!$'\e[0m'
      READY=""
    else
      READY="Done"
    fi
  done

  CLUSTER_FOLDER_REL="clusters/$PROVIDER_NAME/$PROJECT_NAME/$CLUSTER_NAME"
  CLUSTER_FOLDER_ABS="$(dirname "$0")/$CLUSTER_FOLDER_REL"

  if [[ ! -d "$CLUSTER_FOLDER_ABS" ]]; then
    echo "Creating new cluster at $CLUSTER_FOLDER_REL."
    mkdir -p "$CLUSTER_FOLDER_REL/helmsman"
    cp "$DEFAULT_CLUSTER_FOLDER/terraform.tf" "$CLUSTER_FOLDER_ABS"
    cp "$DEFAULT_CLUSTER_FOLDER/example.tf" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"
    cp "$DEFAULT_CLUSTER_FOLDER/helmsman/example.env" "$CLUSTER_FOLDER_ABS/helmsman/$CLUSTER_NAME.env"
    perl -i -pe"s/example_module/${CLUSTER_NAME}_cluster/gm" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"
    perl -i -pe"s/example_location/$CLUSTER_LOCATION/gm" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"
    perl -i -pe"s/example_node_location/$NODE_LOCATION/gm" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"
    perl -i -pe"s/example_project_id/$PROJECT_NAME/gm" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"
    perl -i -pe"s/example_project_id/$PROJECT_NAME/gm" "$CLUSTER_FOLDER_ABS/helmsman/$CLUSTER_NAME.env"
    perl -i -pe"s/example_project_id/$PROJECT_NAME/gm" "$CLUSTER_FOLDER_ABS/terraform.tf"
    perl -i -pe"s/example_cluster_name/$CLUSTER_NAME/gm" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"
    perl -i -pe"s/example_client_config/${CLUSTER_NAME}_client_config/gm" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"
    perl -i -pe"s/example_state/$PROVIDER_NAME-$PROJECT_NAME-$CLUSTER_LOCATION-$CLUSTER_NAME/gm" "$CLUSTER_FOLDER_ABS/terraform.tf"
    perl -i -pe"s/example_client_config/${CLUSTER_NAME}_client_config/gm" "$CLUSTER_FOLDER_ABS/terraform.tf"
    perl -i -pe"s/example_client_config/${CLUSTER_NAME}_client_config/gm" "$CLUSTER_FOLDER_ABS/$CLUSTER_NAME.tf"

    echo "Generating new CI file now."
    exec "$(dirname "$0")/generate-ci.sh"
  else
    echo "The cluster at $CLUSTER_FOLDER_REL already exists. Doing nothing."
    exit 1
  fi
}

printf "Welcome $USER!\n"
welcome_user
check_provider
check_projects
check_cluster_locations
check_node_locations
check_clusters
create_cluster
