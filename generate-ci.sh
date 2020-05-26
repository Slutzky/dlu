#!/usr/bin/env bash

CLOUD_TOOLS_IMAGE="registry.marketlogicsoftware.com/cloud-tools:0.0.4"

cat <<EOF >.gitlab-ci.yml
image: ${CLOUD_TOOLS_IMAGE}

stages:
  - plan-infrastructure
  - apply-infrastructure
  - commit-environments
  - plan-deployments
  - apply-deployments

include:

commit-environments:
  stage: commit-environments
  before_script:
    - mkdir ~/.ssh
    - echo \${SRE_SSH_USER_KEY} | base64 -d > ~/.ssh/id_ed25519
    - chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519
    - cat ~/.ssh/id_ed25519
    - ssh-keyscan -p 10022 git.marketlogicsoftware.com >> ~/.ssh/known_hosts
    - chmod 644 ~/.ssh/known_hosts
    - git config --global user.email "sre_team@marketlogicsoftware.com" && git config --global user.name "automatic_for_the_people"
  script:
    - git clone ssh://git@git.marketlogicsoftware.com:10022/mip/sre/environments.git && cd environments && git checkout master
    - rm -rvf projects/*
    - find ../clusters/gke/ -maxdepth 1 -mindepth 1 ! -regex ".*example_project.*" -exec cp -r {} ./projects/ \;
    - git add -A
    - git diff-index --quiet HEAD || git commit -m "Update environments from bootstrap repo commit \${CI_COMMIT_SHA}"
    - git push origin master || true
  allow_failure: false
  tags:
    - infrastructure
  only:
    - ci_changes

EOF

CLUSTERS=clusters
PROVIDERS="$CLUSTERS/*"
for PROVIDER in $PROVIDERS; do
  for PROVIDER_PATH in "$PROVIDER"/*; do
    for CLUSTER_PATH in "$PROVIDER_PATH"/*; do
        CLUSTER_NAME="$(basename "$PROVIDER_PATH")-$(basename "$CLUSTER_PATH")"
        if [[ ! "$(basename "$CLUSTER_PATH")" == "example_cluster" && ! "$(basename "$PROVIDER_PATH")" == "mip-stable" ]]; then
            LOCATION=$(sed -n 's/cluster_location = \"\(.*\)\"/\1/p' "$CLUSTER_PATH/$(basename "$CLUSTER_PATH").tf" | tr -d ' ')
            KUBECTL_CONFIG=$(echo "\$KUBECONFIG_$(basename "$PROVIDER")_${LOCATION}_$(basename "$CLUSTER_PATH")" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
            cat <<EOF >ci/.$CLUSTER_NAME-ci.yml
plan-${CLUSTER_NAME}:
  stage: plan-infrastructure
  variables:
    KUBERNETES_SERVICE_HOST: "" #https://github.com/terraform-providers/terraform-provider-kubernetes/issues/679#issuecomment-552119320
  script:
    - terraform init -input=false ${CLUSTER_PATH}
    - terraform plan -input=false -out=${CLUSTER_NAME} ${CLUSTER_PATH}
  artifacts:
    paths:
      - .terraform
      - ${CLUSTER_PATH}/helmsman
      - ${CLUSTER_NAME}
    expire_in: 1 days
  allow_failure: true
  tags:
    - infrastructure
  only:
    - ci_changes

apply-${CLUSTER_NAME}:
  stage: apply-infrastructure
  variables:
    TF_LOG: DEBUG
    KUBERNETES_SERVICE_HOST: "" #https://github.com/terraform-providers/terraform-provider-kubernetes/issues/679#issuecomment-552119320
  script:
    - terraform apply -input=false ${CLUSTER_NAME}
  when: manual
  artifacts:
    paths:
      - ${CLUSTER_PATH}/helmsman
  dependencies:
    - plan-${CLUSTER_NAME}
  tags:
    - infrastructure
  only:
    - ci_changes

apply-${CLUSTER_NAME}-helmsman:
  stage: apply-deployments
  before_script:
    - echo "${KUBECTL_CONFIG}" | base64 -d > ${CLUSTER_PATH}/helmsman/$(basename "$CLUSTER_PATH").conf
  script:
    - ./helmsman/deploy ${CLUSTER_PATH} --apply
  when: manual
  dependencies:
    - plan-${CLUSTER_NAME}
    - apply-${CLUSTER_NAME}
  tags:
    - infrastructure
  only:
    - ci_changes

EOF
        fi
    done
  done
done

for ciyml in $(ls ci -1a | grep yml); do
  sed -i "/include:/a \ \ - ci/${ciyml}" .gitlab-ci.yml;
done
