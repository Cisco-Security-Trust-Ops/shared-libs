#!/bin/bash


########################################################################
################ Sync S3 bucket to Aritfactory repo ####################
########################################################################
# Description:
# This script syncs an s3 bucket to an artifactory  repo. To avoid a huge
# propogration of files, it attempts to use a special cache file in the root
# of the bucket called lastArtifactorySync.  The flow is as follows:
#
# validate_params -> Validates all user required params are given

# sync_s3_target_directory - Check for lastArtifactorySync and get its
# timestamp metadata.  If it doesn't exist assume no sync ever done and
# use a timestamp of 0 (epoch).  List all new objects since this timestamp
# and sync them to a local target directory
#
# sync_target_directory_artifactory - Using sha1 checks for artifacts, sync
# missing files up to artifactory
#
# push_new_sync_file - Push a new lastArtifactorySync file to S3 bucket with
# time of when this script was initiated to the metadata of the object
#
# Acknowledge Credit:
# Parts of this code (sync_target_directory_artifactory were leveraged from JFrogDev/project-examples at
# https://github.com/JFrogDev/project-examples/blob/master/bash-example/deploy-folder-by-checksum.sh.
# We want to thank them for the code that we able to port to our project needs


set -e
usage ()
{
    cat <<- _EOF_

#########################################################################################
This script syncs an s3 repository to an artifactory instance
 Options:
 -h or --help              Display the HELP message and exit.
 --artifactory_repo        Name of the repo in artifactory
 --artifactory_url         Artifactory url service endpoint
 --aws_access_key_id       AWS Access Key ID
 --aws_bucket              AWS bucket name
 --aws_secret_access_key   AWS Secret Access Key
 --target_directory        Target directory (default /tmp/sync_s3_artifactory)
_EOF_
}

function error_handler() {
  echo "Error occurred in script at line: ${1}."
  echo "Line exited with status: ${2}"
}

trap 'error_handler ${LINENO} $?' ERR

SCRIPT_EXECUTE_TIME=`date +"%s"`

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

function validate_params() {

  VARS=('ARTIFACTORY_API_TOKEN' 'ARTIFACTORY_REPO'
        'ARTIFACTORY_URL' 'AWS_ACCESS_KEY_ID'
        'AWS_BUCKET'
        'AWS_SECRET_ACCESS_KEY' 'TARGET_DIRECTORY')
  for var in "${VARS[@]}"
  do
    if  [ -z  "${!var}"  ]; then
      echo "Please specify the ${var}"
      exit 1
    fi
  done

}

function sync_s3_target_directory() {
  #Export id and key for aws
  export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
  export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}

  mkdir -p ${TARGET_DIRECTORY}

  #Test callee AWS credentials
  aws sts get-caller-identity

  #Look for ${LAST_ARTIFACTORY_PULL_FILE} metadata and the metadata modify timestamp
  #If first time, no file will exist so set timestamp to epoch '1970-01-01' or int 0
  set +e
  results=`aws s3api head-object --bucket ${AWS_BUCKET} --key ${LAST_ARTIFACTORY_PULL_FILE}`
  exitcode=$?
  set -e
  last_artifactory_sync=0
  if [ $exitcode -eq 0 ]; then
    last_artifactory_sync=`echo $results | jq -r '.Metadata.timestamp'`
  fi
  echo "Last artifactory sync timestamp is `date -d @${last_artifactory_sync}`"

  while true; do

    #We take a sha1 of the whole directory structure to detect changes for later
    previous_checksum=`find ${TARGET_DIRECTORY} -type f -exec sha1sum {} \; | sha1sum | awk '{ print $1 }'`

    #formatted date sync, the query command appears to require a specific format to work properly
    last_artifactory_sync_query_format=`date -d @${last_artifactory_sync} +%FT%T`

    #aws list-objects by timestamp to get the new files to sync
    new_files=( $(aws s3api list-objects --bucket ${AWS_BUCKET} \
                                         --query 'Contents[?LastModified >= `'${last_artifactory_sync_query_format}'`]|[?Size > `0`][].{Key: Key}' | \
                  jq -r '.[] | "\(.Key)"') )

    printf 'New files from s3:\n%s\n' "${new_files[@]}"

    options="--exclude=*"
    for new_file in "${new_files[@]}"; do
      options="${options} --include ${new_file}"
    done

    #Sync aws to target directory
    aws s3 sync ${options} s3://${AWS_BUCKET} ${TARGET_DIRECTORY}

    #This is a little "hacky" but to avoid a race condition where a new release is being generated we check twice
    #for new files.  We sleep for a period then check again after.  If there are no new files found from
    #first check to next then the assumption is the new release has completed.  If new files found, check again.
    #If there are no files found then empty directory will equal empty directory
    current_checksum=`find ${TARGET_DIRECTORY} -type f -exec sha1sum {} \; | sha1sum | awk '{ print $1 }'`
    if [ "${previous_checksum}" = "${current_checksum}" ]; then
      echo "No new files found"
      break
    else
      echo "Sleeping to check for any new files uploaded"
      sleep 15
    fi
  done
}

function sync_target_directory_artifactory() {
  # Upload by checksum all files from the source dir to the target repo
  find "${TARGET_DIRECTORY}" -type f | sort | while read f; do
      rel="$(echo "$f" | sed -e "s#${TARGET_DIRECTORY}##" -e "s# /#/#")";
      sha1=$(sha1sum "$f")
      sha1="${sha1:0:40}"
      printf "\n\nUploading '$f' (cs=${sha1}) to '${ARTIFACTORY_URL}/${ARTIFACTORY_REPO}/${rel}'"
      set +e
      status=$(curl -k --header "X-JFrog-Art-Api: ${ARTIFACTORY_API_TOKEN}" -X PUT -H "X-Checksum-Deploy:true" -H "X-Checksum-Sha1:$sha1" --write-out %{http_code} --silent --output /dev/null "${ARTIFACTORY_URL}/${ARTIFACTORY_REPO}/${rel}")
      set -e
      echo "status=$status"
      # No checksum found - deploy + content
      if [ ${status} -eq 404 ]; then
        curl -k --header "X-JFrog-Art-Api: ${ARTIFACTORY_API_TOKEN}" -H "X-Checksum-Sha1:$sha1" -T "$f" "${ARTIFACTORY_URL}/${ARTIFACTORY_REPO}/${rel}"
      elif [ ${status} -ge 204 -o ${status} -lt 200 ]; then
        echo "Bad status code from curl upload comand: ${status}"
        exit 1
      fi
  done
}

function push_new_sync_file() {

  #Export id and key for aws
  export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
  export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}

  sleep 60
  echo "Setting time of ${TARGET_DIRECTORY}/${LAST_ARTIFACTORY_PULL_FILE} to `date -d @${SCRIPT_EXECUTE_TIME} +%Y%m%d%H%M.%S`"
  touch -t `date -d @${SCRIPT_EXECUTE_TIME} +%Y%m%d%H%M.%S` ${TARGET_DIRECTORY}/${LAST_ARTIFACTORY_PULL_FILE}
  aws s3api put-object --body ${TARGET_DIRECTORY}/${LAST_ARTIFACTORY_PULL_FILE} --key ${LAST_ARTIFACTORY_PULL_FILE}  --bucket ${AWS_BUCKET} \
                       --metadata timestamp=${SCRIPT_EXECUTE_TIME}
}

LAST_ARTIFACTORY_PULL_FILE="lastArtifactorySync"

ARTIFACTORY_API_TOKEN=""
ARTIFACTORY_REPO=""
ARTIFACTORY_URL=""
AWS_ACCESS_KEY_ID=""
AWS_BUCKET=""
AWS_SECRET_ACCESS_KEY=""
TARGET_DIRECTORY="/tmp/sync_s3_artifactory"

for i in "$@"
do
  case $i in
    --artifactory_api_token=*)
      ARTIFACTORY_API_TOKEN="${i#*=}"
      shift
    ;;
    --artifactory_repo=*)
      ARTIFACTORY_REPO="${i#*=}"
      shift
    ;;
    --artifactory_url=*)
      ARTIFACTORY_URL="${i#*=}"
      shift
    ;;
    --aws_access_key_id=*)
      AWS_ACCESS_KEY_ID="${i#*=}"
      shift
    ;;
    --aws_bucket=*)
      AWS_BUCKET="${i#*=}"
      shift
    ;;
    --aws_secret_access_key=*)
      AWS_SECRET_ACCESS_KEY="${i#*=}"
    ;;
    --target_directory=*)
      TARGET_DIRECTORY="${i#*=}"
    ;;
    -h | --help)
      usage
      exit
    ;;
    *)
      echo "Unknown option: $i"
      exit 1
    ;;
  esac
done

validate_params
sync_s3_target_directory
sync_target_directory_artifactory
push_new_sync_file

