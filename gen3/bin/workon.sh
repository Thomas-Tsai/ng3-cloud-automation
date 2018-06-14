#
# Helper script for 'gen3 workon' - see ../README.md and ../gen3setup.sh
#

help() {
  cat - <<EOM
  Use: gen3 workon aws-profile vpc-name
     Prepares a local workspace to run terraform and other devops tools.
EOM
  return 0
}

source "$GEN3_HOME/gen3/lib/utils.sh"
gen3_load "gen3/lib/terraform"
gen3_load "gen3/lib/aws"
gen3_load "gen3/lib/gcp"
gen3_load "gen3/lib/onprem"

#
# Create any missing files
#
mkdir -p -m 0700 "$GEN3_WORKDIR/backups"

if [[ ! -f "$GEN3_WORKDIR/root.tf" ]]; then
  # Note: do not use `` in heredoc!
  echo "Creating $GEN3_WORKDIR/root.tf"
  if [[ "$GEN3_FLAVOR" == "AWS" ]]; then
    cat - > "$GEN3_WORKDIR/root.tf" <<EOM
#
# THIS IS AN AUTOGENERATED FILE (by gen3)
# root.tf is required for *terraform output*, *terraform taint*, etc
# @see https://github.com/hashicorp/terraform/issues/15761
#
terraform {
    backend "s3" {
        encrypt = "true"
    }
}
EOM
  else
    cat - > "$GEN3_WORKDIR/root.tf" <<EOM
#
# THIS IS AN AUTOGENERATED FILE (by gen3)
# root.tf is required for *terraform output*, *terraform taint*, etc
# @see https://github.com/hashicorp/terraform/issues/15761
#
EOM
  fi
fi

#
# Sync the given file with S3.
# Note that 'workon' only every copies from S3 to local,
# and only if a local copy does not already exist.
# See 'gen3 refresh' to pull down latest files from s3.
# We copy the local up to S3 at 'apply' time.
#
refreshFromBackend() {
  local fileName
  local filePath
  fileName=$1
  if [[ -z $fileName ]]; then
    return 1
  fi
  filePath="${GEN3_WORKDIR}/$fileName"
  if [[ -f $filePath ]]; then
    echo "Ignoring S3 refresh for file that already exists: $fileName"
    return 1
  fi
  if [[ "$GEN3_FLAVOR" != "AWS" ]]; then
    #echo -e "$(red_color "refreshFromBackend not yet supported for $GEN3_FLAVOR")"
    return 1
  fi
  s3Path="s3://${GEN3_S3_BUCKET}/${GEN3_WORKSPACE}/${fileName}"
  gen3_aws_run aws s3 cp "$s3Path" "$filePath" > /dev/null 2>&1
  if [[ ! -f "$filePath" ]]; then
    echo "No data at $s3Path"
    return 1
  fi
  return 0
}

for fileName in config.tfvars backend.tfvars README.md; do
  filePath="${GEN3_WORKDIR}/$fileName"
  if [[ ! -f "$filePath" ]]; then
    refreshFromBackend "$fileName"
    if [[ ! -f "$filePath" ]]; then
      echo "Variables not configured at $filePath"
      echo "Setting up initial contents - customize before running terraform"
      # Run the function that corresponds to the profile flavor (AWS, GCP, ...) and $fileName
      "gen3_${GEN3_FLAVOR}.$fileName" > "$filePath"
    fi
  fi
done

cd "$GEN3_WORKDIR"
bucketCheckFlag=".tmp_bucketcheckflag2"
if [[ ! -f "$bucketCheckFlag" && "$GEN3_FLAVOR" == "AWS" ]]; then
  echo "initializing terraform"
  echo "checking if $GEN3_S3_BUCKET bucket exists"
  if ! gen3_aws_run aws s3 ls "s3://$GEN3_S3_BUCKET" > /dev/null 2>&1; then
    echo "Creating $GEN3_S3_BUCKET bucket"
    echo "NOTE: please verify that aws profile region matches backend.tfvars region:"
    echo "  aws profile region: $(aws configure get $GEN3_PROFILE.region)"
    echo "  terraform backend region: $(cat *backend.tfvars | grep region)"

    S3_POLICY=$(cat - <<EOM
  {
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }
EOM
)
    gen3_aws_run aws s3api create-bucket --acl private --bucket "$GEN3_S3_BUCKET"
    sleep 5 # Avoid race conditions
    if gen3_aws_run aws s3api put-bucket-encryption --bucket "$GEN3_S3_BUCKET" --server-side-encryption-configuration "$S3_POLICY"; then
      touch "$bucketCheckFlag"
    fi
  else
    touch "$bucketCheckFlag"
  fi
fi

echo "Running: terraform init --backend-config ./backend.tfvars $GEN3_TFSCRIPT_FOLDER/"
gen3_terraform init --backend-config ./backend.tfvars "$GEN3_TFSCRIPT_FOLDER/"
