#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# imports
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

## Globals

## Functions

usage() {
  echo -n "$(basename "$0") [OPTION]...

Push OLM Bundle Images.

 Options:
  -c, --container-tool     Tool to build image [docker, podman] (default 'docker')
  -d, --directory          The directory where bundle manifests are located (default 'deploy/olm-catalog/${PACKAGE_NAME}')
  -f, --versions-csv       Comma seperated values files containing versions, channels etc
  -h, --help               Display this help and exit
  -i, --image-name         The bundle image name
"
exit 0
}

## Main

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--container-tool)
    CONTAINER_TOOL="$2"
    shift 2
    ;;
    -d | --directory)
    BASE_MANIFESTS_DIR="$2"
    shift 2
    ;;
    -f | --versions-csv)
    VERSIONS_CSV="$2"
    shift 2
    ;;
    -i | --image-name)
    BUNDLE_IMAGE="$2"
    shift 2
    ;;
    -r | --target-reg)
    TARGET_REG="$2"
    shift 2
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
    *)
    POSITIONAL+=("$1")
    shift
    ;;
esac
done
#set -- "${POSITIONAL[@]}"

utils::check_dependencies

TARGET_REG=${TARGET_REG:-$_TARGET_REG}
CHANNELS=${2:-$_CHANNELS}
DEFAULT_CHANNEL=${3:-$_DEFAULT_CHANNEL}

if [ -z "${CONTAINER_TOOL}" ]; then
  CONTAINER_TOOL="docker"
fi

# populate versions table
if [[ -n ${VERSIONS_CSV} ]]; then
    utils::parse_versions_csv "${VERSIONS_CSV}"
else
    utils::parse_deploy_dir "${BASE_MANIFESTS_DIR}" "${CHANNELS}" "${DEFAULT_CHANNEL}"
fi

for v in "${VERSIONS_CSV_ARRAY[@]}"; do
    IFS=', ' read -r -a row <<< "${v}"
    version="v${row[0]}"

    img="${TARGET_REG}/${BUNDLE_IMAGE}:${version}"

    utils::push_image "${img}" "${CONTAINER_TOOL}"
done

exit 0
