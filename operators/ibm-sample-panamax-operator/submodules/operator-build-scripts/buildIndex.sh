#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# It is assumed that this script will be executed on a x86_64, ppc64le or s390x node

# imports
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

local_cleanup() {
    if [ ! -f "${SCRIPT_DIR}/.env" ]; then
      rm "${SCRIPT_DIR}/.env"
    fi
}
trap local_cleanup EXIT

## Functions

usage() {
  echo -n "$(basename "$0") [OPTION]... <target registry> <name of catalog image> <version of final image>

Build OLM Index Image on either a x86_64, ppc64le or s390x node.
  <target registry>        name of target regsitry (e.g. cp.stg.icr.io/cp)
  <name of catalog image>  name of catalog image (e.g. ibm-sample-panamax-catalog)
  
 Options:
  -n, --opm-version        [REQUIRED] Version of opm (e.g. v4.5)
  -b, --base-image         [REQUIRED] The base image that the index will be built upon (e.g. registry.redhat.io/openshift4/ose-operator-registry)
  -t, --output             [REQUIRED] The location where the database was output
  -e, --date               build date (used in automatic tag generation, if used, must supply (-s | --git-sha) see https://github.ibm.com/IBMPrivateCloud/container-content-roadmap/issues/7430#issuecomment-23068783)
  -s, --git-sha            git sha (used in automatic tag generation, if used, must supply (-e | --date) see https://github.ibm.com/IBMPrivateCloud/container-content-roadmap/issues/7430#issuecomment-23068783)
  -g, --tag                catalog image version override
  -h, --description        long description of the application or component in this image
  -m, --summary            short overview of the application or component in this image
  -r, --release            number used to identify the specific build for this image. default ('')
  -u, --final-base-image   name of the final image to use as the base image for the catalog (default 'registry.redhat.io/ubi8/ubi')
  -v, --vendor             vendor to specify for the image vendor label (default 'IBM')
  -c, --container-tool     tool to build image [docker, podman] (default 'docker')
  
  -h, --help               Display this help and exit
"
exit 0
}

create_registry_dockerfile() {

    local version=$1
    local index_dockerfile=${TMP_DIR}/index.dockerfile

    cat << EOF > "${index_dockerfile}"
FROM ${BASE_INDEX_IMG}:${OPM_VERSION} AS builder
FROM ${FINAL_BASE_IMG}
COPY bundles.db /database/index.db
LABEL sample.ibm.com.catalog.version="${version}"
LABEL operators.operatorframework.io.index.database.v1=/database/index.db
LABEL name=${INDEX_IMG}
LABEL vendor=${VENDOR}
LABEL version=${OPM_VERSION}
LABEL release="${RELEASE}"
LABEL summary="${SUMMARY}"
LABEL description="${DESCRIPTION}"
COPY --from=builder /usr/bin/registry-server /registry-server
COPY --from=builder /bin/grpc_health_probe /bin/grpc_health_probe
COPY LICENSE /licenses
EXPOSE 50051
ENTRYPOINT ["/registry-server"]
CMD ["--database", "/database/index.db"]
EOF

}

build_index_image(){

    local img=$1
    echo "------------ building index image ${img} ------------ "
    "${CONTAINER_TOOL}" build -f "${TMP_DIR}"/index.dockerfile -t "${img}" --no-cache "${TMP_DIR}"
}

## DECLARE
INDEX_IMG_VERSION=""

## MAIN

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
    -b|--base-image)
    BASE_INDEX_IMG="$2"
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
    -t|--output)
    TMP_DIR="$2"
    shift 2
    ;;
    -u|--final-base-image)
    FINAL_BASE_IMG="$2"
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

declare -A ArchLookup
ArchLookup=([x86_64]=amd64 [ppc64le]=ppc64le [s390x]=s390x)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [[ -n "${INDEX_IMG_VERSION}" ]]; then
  # If value provided, just use it as-is
  :
elif [[ -n "${CATALOG_BUILD_DATE}" ]] && [[ -n "${GIT_SHA}" ]]; then
  # We have what we need to create the tag automatically
  # TODO: architecture variant is described in spec, but no reliable way to obtain this and we don't need it yet
  INDEX_IMG_VERSION="${OPM_VERSION}-${CATALOG_BUILD_DATE}-${GIT_SHA}-${OS}.${ArchLookup[$(uname -i)]}"
else
  # user failed to provide either values for a tag
  utils::err_exit_no_cleanup "either the combination of (-e | --date) and (-s | --git-sha) OR (-g | --tag) argument required"
fi

if [[ -z "${TMP_DIR}" ]]; then
  utils::err_exit_no_cleanup "-t or --output argument required"
fi

# Directory should already exist, but make sure to avoid confusing errors
mkdir -p "${TMP_DIR}"

# make sure the database is present, if not bail out
if [ ! -f "${TMP_DIR}/bundles.db" ]; then
  utils::err_exit_no_cleanup "Required database ${TMP_DIR}/bundles.db does not exist"
fi

if [[ -z "${OPM_VERSION}" ]]; then
  utils::err_exit_no_cleanup " -n or --opm-version argument required"
fi

if [[ -z "${BASE_INDEX_IMG}" ]]; then
  utils::err_exit_no_cleanup "-b or --base-image argument required"
fi

if [[ -z "${FINAL_BASE_IMG}" ]]; then
  FINAL_BASE_IMG="registry.redhat.io/ubi8/ubi-minimal"
fi

if [[ -z "${CONTAINER_TOOL}" ]]; then
  CONTAINER_TOOL="docker"
fi

if [[ -z "${VENDOR+x}" ]]; then
  VENDOR="IBM"
fi

# If release not specified, try to build it using the date and git sha. Otherwise, leave it blank 
if [[ -z "${RELEASE+x}" ]]; then
  if [[ -n "${CATALOG_BUILD_DATE}" ]] && [[ -n "${GIT_SHA}" ]]; then
    RELEASE=${CATALOG_BUILD_DATE}-${GIT_SHA}
  else
    RELEASE=""
  fi
fi

if [[ -z "${SUMMARY+x}" ]]; then
  SUMMARY="Catalog image for ${INDEX_IMG}"
fi

if [[ -z "${DESCRIPTION+x}" ]]; then
  DESCRIPTION="Catalog image for ${INDEX_IMG}"
fi

echo "pulling correct base image -> ${BASE_INDEX_IMG}:${OPM_VERSION}"
utils::pull_image "${BASE_INDEX_IMG}:${OPM_VERSION}" "${CONTAINER_TOOL}"

echo "Copying license file to ${TMP_DIR}"
cp ${SCRIPT_DIR}/LICENSE ${TMP_DIR}/LICENSE

create_registry_dockerfile "${INDEX_IMG_VERSION}"

img="${TARGET_REG}/${INDEX_IMG}:${INDEX_IMG_VERSION}"

build_index_image "${img}"

exit 0