#!/usr/bin/env bash

set -euo pipefail

# This script goes through an operator's git releases and dynamically
# creates a versions.txt that is used by other scripts in operator-build-scripts
# It also builds the bundle image for each release while it's there
# While users most likely want to do both these steps at the same time, flags are provided to just do one or the other

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# Defaults
CSV_YAML=""
ANNOTATIONS_YAML=""
BUNDLE_IMG_NAME=""
VERSIONS_TXT="./versions.txt"
BASE_DEFAULT_CHANNEL=""
CONTAINER_TOOL="docker"
OPERAND_VERSIONS="0.0.0"
CHANNEL_DESCRIPTION=""
MAKE_VERSIONS=1
MAKE_BUNDLES=1
PUSH=0

usage() {
  echo -n "$(basename "$0") [OPTION]...

Go through an operator's git releases, building their bundle images as it goes, and dynamically create versions.txt to be used by other scripts

 Options:
  -y, --csv-yaml           Location of Cluster Service Version file (required)
  -a, --annotations-yaml   Location of Annotations.yaml file (required unless included with --no-versions-txt)
  -i, --bundle-image       Repository name for bundle image (required unless included with --no-bundle-images)
  -f, --versions-txt       File to save comma seperated values files containing versions, channels etc (default './versions.txt')
  -d, --default-channel    Default channel to be listed in the created versions.txt file, needed only if any release's bundle/metadata/annotations.yaml doesn't specify
  -c, --container-tool     Container tool to use for CLI commands (default 'docker')
      --operand-versions   What to put in 'operandversions' field in versions.txt file
      --channel-desc       What to put in 'description' field in versions.txt file
      --no-versions-txt    If present, only the bundle images will be created, and no versions.txt file
      --no-bundle-images   If present, only the versions.txt file will be created, and not the bundle images
  -p, --push               If present, will push created bundle images to their repo
  -h, --help               Display this help and exit

"
exit 0
}

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -y|--csv-yaml)
    CSV_YAML="$2"
    shift 2
    ;;
    -a|--annotations-yaml)
    ANNOTATIONS_YAML="$2"
    shift 2
    ;;
    -i|--bundle-image)
    BUNDLE_IMG_NAME="$2"
    shift 2
    ;;
    -f|--versions-txt)
    VERSIONS_TXT="$2"
    shift 2
    ;;
    -d|--default-channel)
    BASE_DEFAULT_CHANNEL="$2"
    shift 2
    ;;
    -c|--container-tool)
    CONTAINER_TOOL="$2"
    shift 2
    ;;
    --operand-versions)
    OPERAND_VERSIONS="$2"
    shift 2
    ;;
    --channel-desc)
    CHANNEL_DESCRIPTION="$2"
    shift 2
    ;;
    --no-versions-txt)
    MAKE_VERSIONS=0
    shift 1
    ;;
    --no-bundle-images)
    MAKE_BUNDLES=0
    shift 1
    ;;
    -p|--push)
    PUSH=1
    shift 1
    ;;
    -h|--help)
    usage
    shift
    ;;
    --*=|-*) # unsupported flags
    utils::err_exit "Unsupported flag $1"
    ;;
esac
done

if [[ -z "${CSV_YAML}" ]]; then
  utils::err_exit "--csv-yaml is required"
fi

if [[ -z "${ANNOTATIONS_YAML}" && "${MAKE_VERSIONS}" -eq 1 ]]; then
  utils::err_exit "--annotations-yaml is required (unless no-versions-txt is included)"
fi

if [[ -z "${BUNDLE_IMG_NAME}" && "${MAKE_BUNDLES}" -eq 1 ]]; then
  utils::err_exit "--bundle-image argument is required (unless --no-bundle-images is included)"
fi

utils::check_yq
yq_major=$(yq --version | awk '{print $3}' | awk -F'.' '{print $1}')

START_DIR=$(pwd)
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

# Find yaml field $1 in file $2
# This function abstracts yq V4 from earlier versions, where the structure of the command for searching is very different
# Because the structure of more complex searches changed too (see https://mikefarah.gitbook.io/yq/upgrading-from-v3#finding-nodes),
# it is not equipped to handle such searches. This script only accounts for the leading period that V4 expects, and nothing more.
get_yaml() {
    search=${1}
    file=${2}

    ret=""
    # Handle yq change from V3 to V4
    if [[ "${yq_major}" -gt "3" ]]; then
      search=".${search}" #V4 expects search node to begin with a period, so we add it here
      # yq V4 command
      ret=$(yq eval "${search}" "${file}")
    else
      # yq V3 command
      ret=$(yq r "${file}" "${search}")
    fi

    if [[ "$ret" == "null" ]]; then
      ret=""
    fi
    echo "$ret"
}

extract_and_print_version(){
    # Not making versions.txt, so this code won't make a difference
    if [[ "${MAKE_VERSIONS}" -eq 0 ]]; then
      return
    fi

    CSV_YAML="${1}"
    ANNOTATIONS_YAML="${2}"

    VERSION=$(get_yaml "spec.version" "${CSV_YAML}")
    REPLACES=$(get_yaml 'spec.replaces' "${CSV_YAML}")
    # Seperate version fron name in replaces field
    # shellcheck disable=SC2034
    IFS='.' read -r replaces_name REPLACES <<< "${REPLACES}"
    SKIP_RANGE=$(get_yaml 'metadata.annotations."olm.skipRange"' "${CSV_YAML}")
    DEFAULT_CHANNEL=$(get_yaml 'annotations."operators.operatorframework.io.bundle.channel.default.v1"' "${ANNOTATIONS_YAML}")
    if [[ "${DEFAULT_CHANNEL}" == "" ]]; then
      if [[ "${BASE_DEFAULT_CHANNEL}" == "" ]]; then
        utils::err_exit "No default channel specified for ${VERSION}, and none provided with --default-channel.  Aborting."
      fi
      DEFAULT_CHANNEL=${BASE_DEFAULT_CHANNEL}
    fi
    CHANNELS=$(get_yaml 'annotations."operators.operatorframework.io.bundle.channels.v1"' "${ANNOTATIONS_YAML}")

    printf '"%s"\t,"%s"\t,"%s"\t,"%s"\t,"%s"\t,"%s"\t,"%s"' "${VERSION}" "${REPLACES}" "${SKIP_RANGE}" "${OPERAND_VERSIONS}" "${DEFAULT_CHANNEL}" "${CHANNELS}" "${CHANNEL_DESCRIPTION}"
}


# Find version of the current branch that will be built later if not covered by releases
CURRENT_VERSION="v$(get_yaml 'spec.version' "${CSV_YAML}")"
BUILT_CURRENT=0

releases=()
while IFS= read -r line; do
  releases+=( "$line" )
done < <( git tag -l --sort=version:refname "v*" )

# Create git archives of each release that we're interested in
# TODO: add that the user must run `git fetch --tags --all` first to docs?
for release in "${releases[@]}"
do
  mkdir "${WORKING_DIR}/${release}"
  git archive "${release}" | tar -x -C "${WORKING_DIR}/${release}"
  echo "created archive ${WORKING_DIR}/${release}"
done

# Iterate through archived releases
lines=()
for release in "${releases[@]}"
do
    echo "release to build is ${release}"
    cd "${WORKING_DIR}/${release}"
    
    if [[ "${release}" == "${CURRENT_VERSION}" ]]; then
      BUILT_CURRENT=1
    fi

    # Add the lines to the versions.txt
    lines+=( "$(extract_and_print_version "${CSV_YAML}" "${ANNOTATIONS_YAML}")" )
    
    if [[ "${MAKE_BUNDLES}" -eq 1 ]]; then
      # Build this bundle from the release's Dockerfile (same effect as make bundle-build in that release)
      ${CONTAINER_TOOL} build -f bundle.Dockerfile -t "${BUNDLE_IMG_NAME}:${release}" .
      if [[ "${PUSH}" -eq 1 ]]; then
        utils::push_image "${BUNDLE_IMG_NAME}:${release}" "${CONTAINER_TOOL}"
      fi
    fi
done

cd "$START_DIR"

# Current version not handled by versions.txt, so build it now
if [[ "${BUILT_CURRENT}" -eq 0 ]]; then
  lines+=( "$(extract_and_print_version "${CSV_YAML}" "${ANNOTATIONS_YAML}" "${BASE_DEFAULT_CHANNEL}")" )
  if [[ "${MAKE_BUNDLES}" -eq 1 ]]; then
    ${CONTAINER_TOOL} build -f bundle.Dockerfile -t "${BUNDLE_IMG_NAME}:${CURRENT_VERSION}" .
    if [[ "${PUSH}" -eq 1 ]]; then
      utils::push_image "${BUNDLE_IMG_NAME}:${CURRENT_VERSION}" "${CONTAINER_TOOL}"
    fi
  fi
fi

# Don't go on to create versions.txt if flag was provided
if [[ "${MAKE_VERSIONS}" -eq 0 ]]; then
  exit 0
fi

rm -f "${VERSIONS_TXT}"

echo -e "\"version\"\t,\"replaces\"\t,\"skiprange\"\t,\"operandversions\"\t,\"defaultchannel\"\t,\"channels\"\t,\"description\"" > "$VERSIONS_TXT"

for i in "${!lines[@]}"; do
    echo "${lines[$i]}" >> "${VERSIONS_TXT}"
done
