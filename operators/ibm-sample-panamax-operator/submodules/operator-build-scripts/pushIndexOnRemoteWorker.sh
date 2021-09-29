#!/usr/bin/env bash

set -euo pipefail

# It is assumed that this script will be executed on a given node (e.g. travis worker, local development machine)
# and will execute its work on remote worker nodes using environment vars X_NODE, P_NODE, Z_NODE

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

usage() {
  echo -n "$(basename "$0") [OPTION]... <target registry> <name of catalog image> <version of final image>

Build OLM Index Database on a x86_64 node.
  <target registry>        name of target regsitry (e.g. cp.stg.icr.io/cp)
  <name of catalog image>  name of catalog image (e.g. ibm-sample-panamax-catalog)

 Options:
  -n, --opm-version        [REQUIRED] Version of opm (e.g. v4.5)
  -e, --date               build date (used in automatic tag generation, if used, must supply (-s | --git-sha) see https://github.ibm.com/IBMPrivateCloud/container-content-roadmap/issues/7430#issuecomment-23068783)
  -s, --git-sha            git sha (used in automatic tag generation, if used, must supply (-e | --date) see https://github.ibm.com/IBMPrivateCloud/container-content-roadmap/issues/7430#issuecomment-23068783)
  -g, --tag                catalog image version override
  -c, --container-tool     Tool to build image [docker, podman] (default 'docker')
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
    -n|--opm-version)
    OPM_VERSION="$2"
    shift 2
    ;;
    -e|--date)
    CATALOG_BUILD_DATE="$2"
    shift 2
    ;;
    -s|--git-sha)
    GIT_SHA="$2"
    shift 2
    ;;
    -g|--tag)
    INDEX_IMG_VERSION="$2"
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
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

TARGET_REG="${1:-$_TARGET_REG}"
INDEX_IMG="${2:-$_INDEX_IMG}"

# Copy over all of the scripts (NOTE: we don't use --delete here)
rsync -avL "${SCRIPT_DIR}/" "root@${X_NODE}:index"
rsync -avL "${SCRIPT_DIR}/" "root@${P_NODE}:index"
rsync -avL "${SCRIPT_DIR}/" "root@${Z_NODE}:index"

if [ -n "${INDEX_IMG_VERSION:-}" ]; then
  # If value provided, just use it as-is
  :
elif [ -n "${CATALOG_BUILD_DATE}" ] && [ -n "${GIT_SHA}" ]; then
  # We have what we need to create the tag automatically, except for architecture which is supplied on each node
  # TODO: architecture variant is described in spec, but no reliable way to obtain this and we don't need it yet
  INDEX_IMG_VERSION="${OPM_VERSION}-${CATALOG_BUILD_DATE}-${GIT_SHA}-{os}.{arch}"
else
  # user failed to provie either values for a tag
  utils::err_exit_no_cleanup "either the combination of (-e | --date) and (-s | --git-sha) OR (-g | --tag) argument required"
fi


# now push the index created on each node
PUSH_INDEX="index/pushIndex.sh '${TARGET_REG}' '${INDEX_IMG}' '${INDEX_IMG_VERSION}' '${CONTAINER_TOOL}'"

ssh "root@${X_NODE}" "${PUSH_INDEX}"
ssh "root@${P_NODE}" "${PUSH_INDEX}"
ssh "root@${Z_NODE}" "${PUSH_INDEX}"

# since we know the x86_64 is already logged in, use it to create the manifest
ssh "root@${X_NODE}" "index/buildManifest.sh --image-name-base '${TARGET_REG}/${INDEX_IMG}:${OPM_VERSION}-${CATALOG_BUILD_DATE}-${GIT_SHA}' --image-name-template '{base}-{os}.{arch}' --platforms 'amd64,ppc64le,s390x' --container-tool ${CONTAINER_TOOL} && ${CONTAINER_TOOL} manifest push '${TARGET_REG}/${INDEX_IMG}:${OPM_VERSION}-${CATALOG_BUILD_DATE}-${GIT_SHA}'"

