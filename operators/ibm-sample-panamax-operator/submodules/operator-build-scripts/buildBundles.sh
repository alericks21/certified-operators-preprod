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

Build OLM Bundle Images.

 Options:
  -c, --container-tool     Tool to build image [docker, podman] (default 'docker')
  -o, --opm-tool           Name of the opm tool
  -d, --directory          The directory where bundle manifests are located (default 'deploy/olm-catalog/${PACKAGE_NAME}')
  -f, --versions-csv       Comma seperated values files containing versions, channels etc
  -h, --help               Display this help and exit
  -i, --image-name         The bundle image name
"
exit 0
}

build_bundle_image(){

    local img=$1
    local directory=$2
    local channels=$3
    local default_channel=$4
    local container_tool=$5
    local opm_tool=$6

    echo "------------ building ${img} ------------"
    operator-sdk bundle create "${img}" \
        --directory "${directory}" \
        --package "${PACKAGE_NAME}" \
        --channels "${channels}" \
        --default-channel "${default_channel}" \
        --image-builder "${container_tool}"

    # "${opm_tool}" alpha bundle build --tag "${img}" \
    #     --directory "${directory}" \
    #     --package "${PACKAGE_NAME}" \
    #     --channels "${channels}" \
    #     --default "${default_channel}" \
    #     --overwrite
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
    -o|--opm-tool)
    OPM_TOOL="$2"
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

# populate versions table
if [[ -n ${VERSIONS_CSV} ]]; then
    utils::parse_versions_csv "${VERSIONS_CSV}"
else
    utils::parse_deploy_dir "${BASE_MANIFESTS_DIR}" "${CHANNELS}" "${DEFAULT_CHANNEL}"
fi

if [ -z "${CONTAINER_TOOL}" ]; then
  CONTAINER_TOOL="docker"
fi

if [ -z "${OPM_TOOL}" ]; then
  OPM_TOOL="opm"
fi

utils::check_opm

for v in "${VERSIONS_CSV_ARRAY[@]}"; do
    IFS=', ' read -r -a row <<< "${v}"
    version="v${row[0]}"
    dir="${row[1]}"
    channels="${row[2]}"
    defaultchannel="${row[3]}"

    img="${TARGET_REG}/${BUNDLE_IMAGE}:${version}"

    build_bundle_image "${img}" "${dir}" "${channels}" "${defaultchannel}" "${CONTAINER_TOOL}" "${OPM_TOOL}"
done

exit 0