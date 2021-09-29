#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# It is assumed that this script will be executed on a x86_64 node

# imports
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

local_cleanup() {
    if [ ! -f "${SCRIPT_DIR}/.env" ]; then
      rm "${SCRIPT_DIR}/.env"
    fi
}
trap local_cleanup EXIT

## Functions

usage() {
  echo -n "$(basename "$0") [OPTION]... <target registry> <name of catalog image> <version of final image>

Build OLM Index Database on a x86_64 node.
  <target registry>        name of target regsitry (e.g. cp.stg.icr.io/cp)

 Options:
  -n, --opm-version        [REQUIRED] Version of opm (e.g. v4.5)
  -b, --base-image         [REQUIRED] The base image that the index will be built upon (e.g. registry.redhat.io/openshift4/ose-operator-registry)
  -t, --output             [REQUIRED] The location where the database should be output
  -i, --image-name         [REQUIRED] The bundle image name
  -c, --container-tool     Tool to build image [docker, podman] (default 'docker')
  -o, --opm-tool           Name of the opm tool (default 'opm')
  -d, --directory          The directory where bundle manifests are located (default 'deploy/olm-catalog/${PACKAGE_NAME}') (either this option or -f, --versions-csv must be provided)
  -f, --versions-csv       Comma seperated values files containing versions, channels etc (either this option or -d, --directory must be provided)
  --debug                  Show debug output
  -h, --help               Display this help and exit

"
exit 0
}


create_empty_db(){

    mkdir -p "${TMP_DIR}/manifests"
    echo "creating a empty bundles.db ..."
    ${CONTAINER_TOOL} run --rm -v "${TMP_DIR}":/tmp --entrypoint "/bin/initializer" "${BASE_INDEX_IMG}:${OPM_VERSION}" -m /tmp/manifests -o /tmp/bundles.db
}

add_to_db(){

    local img=$1
    echo "------------ adding bundle image ${img} to db ------------"
    "${OPM_TOOL}" registry add -b "${img}" -d "${TMP_DIR}/bundles.db" "${OPM_DEBUG_FLAG}"
}

## MAIN

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
    -n|--opm-version)
    OPM_VERSION="$2"
    shift 2
    ;;
    -b|--base-image)
    BASE_INDEX_IMG="$2"
    shift 2
    ;;
    -t | --output)
    TMP_DIR="$2"
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
    -i|--image-name)
    BUNDLE_IMAGE="$2"
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
    *)
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

TARGET_REG="${1:-$_TARGET_REG}"

if [ -z "${TMP_DIR}" ]; then
  err_exit_no_cleanup "-t or --output argument required"
fi

mkdir -p "${TMP_DIR}"
chmod 777 "${TMP_DIR}"

# one of these options has to be provided
if [ -z "${BASE_MANIFESTS_DIR}" ] && [ -z "${VERSIONS_CSV}" ]; then
  utils::err_exit_no_cleanup "either (-d | --directory) or (-f | --versions-csv) argument required"
fi

if [ -z "${OPM_VERSION}" ]; then
  utils::err_exit_no_cleanup " -n or --opm-version argument required"
fi

if [ -z "${BASE_INDEX_IMG}" ]; then
  utils::err_exit_no_cleanup "-b or --base-image argument required"
fi

if [ -z "${BUNDLE_IMAGE}" ]; then
  utils::err_exit_no_cleanup "-i or --image-name argument required"
fi

if [[ ${DEBUG} -eq 1 ]]; then
    utils::enable_debug
fi

if [ -z "${CONTAINER_TOOL}" ]; then
  CONTAINER_TOOL="docker"
fi

if [ -z "${OPM_TOOL}" ]; then
  OPM_TOOL="opm"
fi

utils::check_opm

# NOTE: this script can only be run on x86_64 nodes so check for the require tools
utils::check_skopeo
utils::check_jq

echo "pulling correct base image -> ${BASE_INDEX_IMG}:${OPM_VERSION}"
utils::pull_image "${BASE_INDEX_IMG}:${OPM_VERSION}" "${CONTAINER_TOOL}"

create_empty_db

# populate versions table
if [[ -n ${VERSIONS_CSV} ]]; then
    utils::parse_versions_csv "${VERSIONS_CSV}"
else
    utils::parse_deploy_dir "${BASE_MANIFESTS_DIR}" "${_CHANNELS}" "${_DEFAULT_CHANNEL}"
fi

for v in "${VERSIONS_CSV_ARRAY[@]}"; do
    IFS=', ' read -r -a row <<< "${v}"
    version="v${row[0]}"

    # replace with version with digest
    img="${TARGET_REG}/${BUNDLE_IMAGE}:${version}"
    digest=$( utils::get_digest "${img}")
    img="${TARGET_REG}/${BUNDLE_IMAGE}@${digest}"

    #TODO: skip versions that already
    add_to_db "${img}"
done

echo "rsync database to remote nodes"

# copy the database from the x86_64 node to the other nodes
rsync -avL "${TMP_DIR}" "root@${P_NODE}:/tmp"
rsync -avL "${TMP_DIR}" "root@${Z_NODE}:/tmp"

exit 0