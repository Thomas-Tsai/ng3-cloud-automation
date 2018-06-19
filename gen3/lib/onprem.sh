#!/bin/bash
#
# gcp related helper funcitons for gen3
# Generally assume this is sourced by a parent script that imports utils.sh
#

gen3_load "gen3/lib/utils"

#
# Setup and access terraform workspace for AWS - 
#   delegate for `gen3 workon ...`
#
gen3_workon_onprem(){
  export GEN3_PROFILE="$1"
  export GEN3_WORKSPACE="$2"
  export GEN3_FLAVOR="ONPREM"
  export GEN3_WORKDIR="$XDG_DATA_HOME/gen3/${GEN3_PROFILE}/${GEN3_WORKSPACE}"
  (
# Generate some k8s helper scripts for on-prem deployments
if ! [[ "$GEN3_WORKSPACE" =~ _user$ || "$GEN3_WORKSPACE" =~ _snapshot$ || "$GEN3_WORKSPACE" =~ _adminvm$ || "$GEN3_WORKSPACE" =~ _databucket$ || "$GEN3_WORKSPACE" =~ _logging$  || "$GEN3_WORKSPACE" =~ _squidvm$ ]]; then
  mkdir -p -m 0700 "${GEN3_WORKDIR}/onprem_scripts"
  cd "${GEN3_WORKDIR}"
  cat - > onprem_scripts/kube-setup.sh <<EOM
#
# Bootstrap on-prem k8s setup.
#   source kube-vars.sh
#
set -e
export vpc_name='${GEN3_WORKSPACE}'
export GEN3_HOME="\${GEN3_HOME:-"\$HOME"}"
cd \$HOME
if [[ ! -d "\$GEN3_HOME" ]]; then
  (
    cd "\$(dirname "\$GEN3_HOME")"
    git clone https://github.com/uc-cdis/cloud-automation.git
  )
fi
source "\${GEN3_HOME}/gen3/gen3setup.sh"
gen3 kube-setup-workvm

for fname in 00configmap.yaml creds.json; do
  if [[ ! -f "./\${vpc_name}/\$name" ]]; then
    if [[ -f "./\${vpc_name}_output/\$name" ]]; then
      mkdir -p "./\${vpc_name}"
      cp "\${vpc_name}_output/\$name" "./\${vpc_name}/"
      mv "\${vpc_name}_output/\$name" "\${vpc_name}_output/\${name}.old"
    else
      echo "WARNING: could not find \$name"
    fi
  fi
done

cat - <<EOB
Success!
source ~/.bashrc or ~/.zshrc as appropriate, 
and you'll be ready to run:
  gen3 roll all
EOB

EOM

  if [[ ! -f onprem_scripts/creds.json ]]; then
    (
      export fence_host="postgres-service"
      export fence_user=fence
      export fence_pwd=$(gen3 random)
      export hostname="minikube.planx-pla.net"
      export google_client_secret="look-it-up"
      export google_client_id="look-it-up"
      export indexd_host="postgres-service"
      export indexd_user="indexd_user"
      export indexd_pwd=$(gen3 random)
      export hmac_key="$(gen3 random 32 | base64)"
      export gdcapi_host="postgres-service"
      export sheepdog_user="sheepdog"
      export sheepdog_pwd="$(gen3 random)"
      export gdcapi_user="sheepdog"
      export gdcapi_pwd="${sheepdog_pwd}"
      export gdcapi_db="gdcapi"
      export peregrine_user="peregrine"
      export peregrine_pwd="$(gen3 random)"
      export gdcapi_secret_key="$(gen3 random 50)"
      export gdcapi_oauth2_client_id="n/a"
      export gdcapi_oauth2_client_secret="n/a"

      templatePath="$GEN3_HOME/tf_files/shared/modules/k8s_configs/creds.tpl"
      if [[ -f "$templatePath" ]]; then
        cat "$templatePath" | envsubst > onprem_scripts/creds.json
      fi
    )
  else
    echo "onprem_scripts/creds.json already exists ..."
  fi
  if [[ ! -f onprem_scripts/00configmap.yaml ]]; then
    (
      export vpc_name
      export hostname="minkube.planx-pla.net"
      export revproxy_arn="not-used"
      export logs_bucket="not-used"
      export kube_bucket="not-used"
      export config_folder="CONFIG-FOLDER-NAME-HERE"
      export portal_app=dev
      export dictionary_url="https://s3.amazonaws.com/dictionary-artifacts/datadictionary/develop/schema.json"
      
      templatePath="$GEN3_HOME/tf_files/shared/modules/k8s_configs/00configmap.yaml"
      if [[ -f "$templatePath" ]]; then
        cat "$templatePath" | envsubst > onprem_scripts/00configmap.yaml
      fi
    )
  else
    echo "onprem_scripts/00configmap.yaml already exists ..."
  fi
  if [[ ! -f onprem_scripts/README.md ]]; then
    cat - > onprem_scripts/README.md <<EOM
# TL;DR

This folder contains scripts intended to help bootstrap gen3 k8s services
in an on-prem k8s cluster.  The scripts are auto-generated by *gen3 workon*, and can
take the place of the scripts that terraform generates under *VPCNAME_output/*
for AWS commons deployments.

# On prem process

Something like the following should work to bootstrap an on prem commons:

* Configure the variables in *onprem_scripts/creds.json* and *onprem_scripts/00configmap.yaml*,
  and verify that *onprem_scripts/kube-setup.sh* sets the right *vpc_name* at the top of the script.
* *rsync onprem_scripts/ bastion.host:{VPC_NAME}_output/*
* ssh to bastion.host, and verify that *kubectl* works - ex: *kubectl get nodes*
* setup the proxy environment - either set GEN3_NOPROXY or http_proxy, https_proxy, and no_proxy:
\`\`\`
export GEN3_NOPROXY='$GEN3_NOPROXY'
if [[ -z "\$GEN3_NOPROXY" ]]; then
  export http_proxy='${http_proxy:-"http://cloud-proxy.internal.io:3128"}'
  export https_proxy='${https_proxy:-"http://cloud-proxy.internal.io:3128"}'
  export no_proxy='$no_proxy'
fi
\`\`\`

* bash "${GEN3_WORKSPACE}_output/kube-setup.sh"

EOM
  fi

  if [[ ! -f onprem_scripts/minikube_up.sh ]]; then
    cat - > onprem_scripts/minikube_up.sh <<EOM
#!/bin/bash

if sudo -n true > /dev/null 2>&1; then
  echo "ERROR: minikube_up requires sudo"
  exit 1
fi
if [[ \$(uname -s) != "Linux" ]]; then
  echo "ERROR: minikube_up runs on Linux"
  exit 1
fi

source "\${GEN3_HOME}/gen3/gen3setup.sh"
gen3 kube-setup-workvm "${GEN3_WORKSPACE}"

mkdir -p \$HOME/.local/bin
cd \$HOME/.local/bin
if [[ ! -f minikube ]]; then
  curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && chmod +x minikube
fi
# kube-setup-workvm installs kubectl 
#curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl

if ! which docker > /dev/null 2>&1; then
  sudo apt-get install -y apt-transport-https
  sudo apt-get install -y ca-certificates
  sudo apt-get install -y software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable"
  sudo apt update
  sudo apt install -y docker-ce
fi

export MINIKUBE_WANTUPDATENOTIFICATION=false
export MINIKUBE_WANTREPORTERRORPROMPT=false
export MINIKUBE_HOME=\$HOME
export CHANGE_MINIKUBE_NONE_USER=true
mkdir \$HOME/.kube || true
touch \$HOME/.kube/config

export KUBECONFIG=\$HOME/.kube/config
echo "Run minikube locally with: sudo -E ./minikube start --vm-driver=none"
EOM
  fi

fi
  )

  PS1="gen3/${GEN3_WORKSPACE}:$GEN3_PS1_OLD"
}


#
# Generate an initial backend.tfvars file with intelligent defaults
# where possible.
#
gen3_ONPREM.backend.tfvars() {
  cat - <<EOM
EOM
}

gen3_ONPREM.README.md() {
  cat - <<EOM
# TL;DR

Any special notes about $GEN3_WORKSPACE

## Useful commands

* gen3 help

EOM
}


#
# Generate an initial config.tfvars file with intelligent defaults
# where possible.
#
gen3_ONPREM.config.tfvars() {
  cat - <<EOM
# refer to onprem_scripts/
EOM
}

