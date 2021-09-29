#!/usr/bin/env bash

set -euo pipefail

OPERATOR=ibm-sample-panamax-operator
IMG=''

declare -a BUNDLE_ARRAY

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# imports
# shellcheck source=build/scripts/utils.sh

#source "${SCRIPT_DIR}/utils.sh"

WORKING_DIR=$(mktemp -d)

# check if tmp dir was created
if [[ ! "$WORKING_DIR" || ! -d "$WORKING_DIR" ]]; then
  echo "Could not create temp dir"
  exit 1
fi

# deletes the temp directory
function cleanup {      
  rm -rf "$WORKING_DIR"
  echo "Deleted temp working directory $WORKING_DIR"
}

# register the cleanup function to be called on the EXIT signal
trap cleanup EXIT

#WORKING_DIR="$( cd ../working  && pwd )"
echo "script dir is '$SCRIPT_DIR'"
echo "working dir is '$WORKING_DIR'"

echo "cd $WORKING_DIR"
cd $WORKING_DIR

echo "git clone git@github.ibm.com:CloudPakOpenContent/ibm-sample-panamax-operator.git"
git clone git@github.ibm.com:CloudPakOpenContent/$OPERATOR.git

echo "cd ./ibm-sample-panamax-operator"
cd ./$OPERATOR


for release in $(git tag -l --sort=version:refname "v*")
do
    echo "release to build is ${release}"
    git checkout ${release}

    #the default makefile does not include the v!
    # Current Operator version
    # VERSION ?= 3.0.6

    echo "building bundle"
    #using the default bundle-build that ships with sdk 1
    make bundle-build

    #hack strip off the first char
    IMG=quay.io/huizenga/$OPERATOR-bundle:${release:1}
    docker push $IMG
    #digest=$( utils::get_digest_no_creds "${IMG}")
    #echo "skopeo digest: $digest"
    #echo "$IMG@$digest" >> output.txt

    echo "adding $IMG to array"
    BUNDLE_ARRAY+=($IMG)

    #opm index add -c docker --bundles $IMG --from-index quay.io/huizenga/$OPERATOR-index:latest --tag  quay.io/huizenga/$OPERATOR-index:latest --mode semver-skippatch --permissive
done

# for loop that iterates over each element in arr
echo " array size -> ${#BUNDLE_ARRAY[@]}"
output=""
for i in "${BUNDLE_ARRAY[@]}"
do
    echo "len is ${#output}"

    if [ ${#output} -eq 0 ]; then
        output="$i"
    else
        output="$output,$i"
    fi
done

echo "preparing to remove $OPERATOR from index"
echo "running --> docker pull quay.io/huizenga/$OPERATOR-index:latest"
docker pull quay.io/huizenga/$OPERATOR-index:latest

echo "running --> opm version"
opm version

echo "running --> opm index rm -c docker --from-index quay.io/huizenga/$OPERATOR-index:latest --operators $OPERATOR --tag quay.io/huizenga/$OPERATOR-index:working"
opm index rm -c docker --from-index quay.io/huizenga/$OPERATOR-index:latest --operators $OPERATOR --tag quay.io/huizenga/$OPERATOR-index:working

echo "running --> docker push quay.io/huizenga/$OPERATOR-index:working"
docker push quay.io/huizenga/$OPERATOR-index:working

echo "re-add all of them $output"
echo "running ---> opm index add -c docker --bundles  $output --from-index quay.io/huizenga/$OPERATOR-index:working --tag  quay.io/huizenga/$OPERATOR-index:latest"
opm index add -c docker --bundles  $output --from-index quay.io/huizenga/$OPERATOR-index:working --tag  quay.io/huizenga/$OPERATOR-index:latest

echo "running --> docker push quay.io/huizenga/$OPERATOR-index:latest"
docker push quay.io/huizenga/$OPERATOR-index:latest

exit 0