#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# imports
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

## Functions

usage() {
  echo -n "$(basename "$0") [OPTION]...

Builds the fat manifest image for a multi-platform image.

 Options:
   -c, --container-tool      Tool to build image [docker, podman] (default 'docker') - currently only supports docker
   --debug                   Show debug output
   -h, --help                Display this help and exit
   -b, --image-name-base     The base portion of the image used to identify the fat manitfest, and be used as a template
                             examples: 
                               cp.stg.icr.io/cp/ibm-sample-panamax-operator:20200505112436
                               cp.stg.icr.io/cp/ibm-sample-panamax-catalog:v4.5-20200902.220310-CE62727AE
   -i, --image-name-template A template for the image name of the fat manifest which is used for looking up architecture specific image. The template must include 
                             {base} and {arch} but can optionally include {os}.
                             examples: 
                               {base}-{arch}
                               {base}-{os}.{arch}
   -p, --platforms           A comma-separated list of platforms (default: 'amd64')
                             Note: The assumption is that the platform images have been tagged with the fat manifest image tag + '-platform'. i.e. 1.0.0-amd64
"
exit 0
}

create_manifest() {
  ${CONTAINER_TOOL} manifest create "$MANIFEST_IMAGE" "$@"
}

annotate_manifest() {
  local platformImg=$1
  local platform=$2
  local os=$3
  ${CONTAINER_TOOL} manifest annotate "${MANIFEST_IMAGE}" "${platformImg}" --arch "${platform}" --os "${os}"
}

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--container-tool)
    CONTAINER_TOOL="$2"
    shift 2
    ;;
    -b|--image-name-base)
    MANIFEST_IMAGE="$2"
    shift 2
    ;;
    -i|--image-name-template)
    MANIFEST_IMAGE_TEMPLATE="$2"
    shift 2
    ;;
    -p|--platforms)
    PLATFORMS="$2"
    shift 2
    ;;
    --debug)
    DEBUG=1
    shift
    ;;
    -h|--help)
    usage
    shift
    ;;
    --) # end argument parsing
    shift
    break
    ;;
    --*=|-*) # unsupported flags
    utils::err_exit "Unsupported flag $1"
    ;;
esac
done

if [[ ${DEBUG} -eq 1 ]]; then
    utils::enable_debug
fi

# Verify that skopeo is installed
command -v skopeo >/dev/null 2>&1 || utils::err_exit "skopeo is required but it's not installed. Aborting."

# Verify that CP_CREDS are set
if [ -z "${CP_CREDS+x}" ]; then
  utils::err_exit_no_cleanup "CP_CREDS must be set to retrieve the image digest for the platform images. Aborting."
fi

if [ -z "${MANIFEST_IMAGE+x}" ]; then
  utils::err_exit_no_cleanup "The -b|--image-name-base must be set. Aborting."
fi

if [ -z "${MANIFEST_IMAGE_TEMPLATE+x}" ]; then
  utils::err_exit_no_cleanup "The -i|--image-name-template must be set. Aborting."
fi

# replace the base template first
PROCESSED_MANIFEST_IMAGE="${MANIFEST_IMAGE_TEMPLATE/\{base\}/${MANIFEST_IMAGE}}"
# TODO stop hard coding linux... this should be parameter which allows for passing an array of OS (e.g. linux,windows)
# replace the os next
PROCESSED_MANIFEST_IMAGE="${PROCESSED_MANIFEST_IMAGE/\{os\}/linux}"

# Use the specified container tool (currently only docker, so this flag is ignored)
#if [ -z "${CONTAINER_TOOL}" ]; then
CONTAINER_TOOL="docker"
#fi

# Default platforms if they were not specified
if [ -x "${PLATFORMS}" ]; then
  PLATFORMS="amd64"
fi

# Split the platform lists
IFS=','
read -ra platformList <<< "$PLATFORMS"
IFS=':'
read -ra imageParts <<< "$MANIFEST_IMAGE"
unset IFS

imageNoTag=${imageParts[0]}

# Retrieve digests of the platform images
digests=()
for i in "${platformList[@]}"; do
  # replace the {arch} template with the current platform value i
  echo "Getting digest for ${PROCESSED_MANIFEST_IMAGE/\{arch\}/${i}}"
  digests+=( "$(utils::get_digest "${PROCESSED_MANIFEST_IMAGE/\{arch\}/${i}}")" )
done

# Create list of platform images
platformImages=()
for i in "${digests[@]}"; do
  platformImages+=( "${imageNoTag}@$i")
done

# Create the manifest list
create_manifest "${platformImages[@]}"

# Annotate the manifest list
ITER=0
for i in "${platformImages[@]}"; do
  # TODO stop hard coding linux... 
  annotate_manifest "$i" "${platformList[$ITER]}" "linux"
  ITER=$((ITER+1))
done

# Print out the new manifest
${CONTAINER_TOOL} manifest inspect "${MANIFEST_IMAGE}"