#!/usr/bin/env bash

set -euo pipefail

# It is assumed that this script will be executed on a given node (e.g. travis worker, local development machine)
# and will execute its work on remote worker nodes using environment vars X_NODE, P_NODE, Z_NODE

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

TAG_PASSTHROUGH_ARGS=""

# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

remote_cleanup() {
  # shellcheck disable=SC2029
  ssh "root@${X_NODE}" "rm -rf '${REMOTE_TMP_DIR}'"
  # shellcheck disable=SC2029
  ssh "root@${P_NODE}" "rm -rf '${REMOTE_TMP_DIR}'"
  # shellcheck disable=SC2029
  ssh "root@${Z_NODE}" "rm -rf '${REMOTE_TMP_DIR}'"
}
trap remote_cleanup EXIT

# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

usage() {
  echo -n "$(basename "$0") [OPTION]... <target registry> <name of catalog image> <version of final image>

Build OLM Index Database on a x86_64 node.
  <target registry>        name of target regsitry (e.g. cp.stg.icr.io/cp)
  <name of catalog image>  name of catalog image (e.g. ibm-sample-panamax-catalog)

 Options:
  -n, --opm-version        [REQUIRED] Version of opm (e.g. v4.5)
  -b, --base-image         [REQUIRED] The base image that the index will be built upon (e.g. registry.redhat.io/openshift4/ose-operator-registry)
  -i, --image-name         [REQUIRED] The bundle image name
  -u, --final-base-image   Name of the final image to use as the base image for the catalog (default 'registry.redhat.io/ubi8/ubi')
  -e, --date               build date (used in automatic tag generation, if used, must supply (-s | --git-sha) see https://github.ibm.com/IBMPrivateCloud/container-content-roadmap/issues/7430#issuecomment-23068783)
  -s, --git-sha            git sha (used in automatic tag generation, if used, must supply (-e | --date) see https://github.ibm.com/IBMPrivateCloud/container-content-roadmap/issues/7430#issuecomment-23068783)
  -g, --tag                catalog image version override
  -c, --container-tool     Tool to build image [docker, podman] (default 'docker')
  -o, --opm-tool           Name of the opm tool (default 'opm')
  -d, --directory          The directory where bundle manifests are located (default 'deploy/olm-catalog/${PACKAGE_NAME}') (either this option or -f, --versions-csv must be provided)
  -f, --versions-csv       Comma seperated values files containing versions, channels etc (either this option or -d, --directory must be provided)
  -h, --description        long description of the application or component in this image
  -m, --summary            short overview of the application or component in this image
  -r, --release            number used to identify the specific build for this image. default ('')
  -v, --vendor             vendor to specify for the image vendor label (default 'IBM')
  --debug                  Show debug output
  -h, --help               Display this help and exit

"
exit 0
}

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
    -u|--final-base-image)
    FINAL_BASE_IMG="$2"
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
    -e|--date)
    TAG_PASSTHROUGH_ARGS="${TAG_PASSTHROUGH_ARGS} --date '$2'"
    shift 2
    ;;
    -s|--git-sha)
    TAG_PASSTHROUGH_ARGS="${TAG_PASSTHROUGH_ARGS} --git-sha '$2'"
    shift 2
    ;;
    -g|--tag)
    TAG_PASSTHROUGH_ARGS="${TAG_PASSTHROUGH_ARGS} --tag '$2'"
    shift 2
    ;;
    -h|--description)
    DESCRIPTION="$2"
    shift 2
    ;;
    -m|--summary)
    SUMMARY="$2"
    shift 2
    ;;
    -r|--release)
    RELEASE="$2"
    shift 2
    ;;
    -v|--vendor)
    VENDOR="$2"
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
INDEX_IMG="${2:-$_INDEX_IMG}"

if [ -z "${OPM_VERSION}" ]; then
  utils::err_exit_no_cleanup " -n or --opm-version argument required"
fi

if [ -z "${BASE_INDEX_IMG}" ]; then
  utils::err_exit_no_cleanup "-b or --base-image argument required"
fi

if [ -z "${FINAL_BASE_IMG}" ]; then
  FINAL_BASE_IMG="registry.redhat.io/ubi8/ubi"
fi

if [ -z "${BUNDLE_IMAGE}" ]; then
  utils::err_exit_no_cleanup "-i or --image-name argument required"
fi

if [ -z "${TAG_PASSTHROUGH_ARGS}" ]; then
  utils::err_exit_no_cleanup "either the combination of (-e | --date) and (-s | --git-sha) OR (-g | --tag) argument required"
fi

if [ -z "${CONTAINER_TOOL}" ]; then
  CONTAINER_TOOL="docker"
fi

if [ -z "${OPM_TOOL}" ]; then
  OPM_TOOL="opm"
fi



# setup base folders where we can dump files
ssh "root@${X_NODE}" 'mkdir -p index/versions; mkdir -p index/manifests'

# Copy over all of the scripts
rsync -avL "${SCRIPT_DIR}/" "root@${X_NODE}:index"
rsync -avL "${SCRIPT_DIR}/" "root@${P_NODE}:index"
rsync -avL "${SCRIPT_DIR}/" "root@${Z_NODE}:index"

# define a unique temp directory for use on other systems
REMOTE_TMP_DIR=$(utils::create_tmpdir "print only")
echo "Will use ${REMOTE_TMP_DIR} for the remote temporary directory"

if [[ ${DEBUG} -eq 1 ]]; then
    passthrough_debug="--debug"
else
    passthrough_debug=""
fi

# populate version information and build the database on the x86_64 node
if [[ -n ${VERSIONS_CSV} ]]; then
    VERSIONS_CSV_FILE_NAME="$(basename -- "${VERSIONS_CSV}")"
    rsync -avL "${VERSIONS_CSV}" "root@${X_NODE}:index/versions"
    BUILD_INDEX_DATABASE_COMMAND="index/buildIndexDatabase.sh '${TARGET_REG}' --versions-csv 'index/versions/${VERSIONS_CSV_FILE_NAME}' --image-name '${BUNDLE_IMAGE}' --base-image '${BASE_INDEX_IMG}' --opm-version '${OPM_VERSION}' --container-tool '${CONTAINER_TOOL}' ${passthrough_debug} --opm-tool '${OPM_TOOL}' --output '${REMOTE_TMP_DIR}'"
else
    rsync -avL "${BASE_MANIFESTS_DIR}" "root@${X_NODE}:index/manifests"
    BUILD_INDEX_DATABASE_COMMAND="index/buildIndexDatabase.sh '${TARGET_REG}' --directory 'index/manifests' --image-name '${BUNDLE_IMAGE}' --base-image '${BASE_INDEX_IMG}' --opm-version '${OPM_VERSION}' --container-tool '${CONTAINER_TOOL}' ${passthrough_debug} --opm-tool '${OPM_TOOL}' --output '${REMOTE_TMP_DIR}'"
fi

BUILD_INDEX_DATABASE="index/buildIndex.sh '${TARGET_REG}' '${INDEX_IMG}' ${TAG_PASSTHROUGH_ARGS} --base-image '${BASE_INDEX_IMG}' --final-base-image '${FINAL_BASE_IMG}' --container-tool '${CONTAINER_TOOL}' --opm-version '${OPM_VERSION}' --output '${REMOTE_TMP_DIR}' --description '${DESCRIPTION}' --summary '${SUMMARY}' --release '${RELEASE}' --vendor '${VENDOR}'"

# x86_64 node need to create database and then create index using that database
X_NODE_COMMAND="${BUILD_INDEX_DATABASE_COMMAND} && ${BUILD_INDEX_DATABASE}"
# ppc64le or s390x node just need to create the index using the database created on x86_64 node
P_NODE_COMMAND="${BUILD_INDEX_DATABASE}"
Z_NODE_COMMAND="${BUILD_INDEX_DATABASE}"


# shellcheck disable=SC2029
ssh "root@${X_NODE}" "${X_NODE_COMMAND}"
# shellcheck disable=SC2029
ssh "root@${P_NODE}" "${P_NODE_COMMAND}"
# shellcheck disable=SC2029
ssh "root@${Z_NODE}" "${Z_NODE_COMMAND}"
