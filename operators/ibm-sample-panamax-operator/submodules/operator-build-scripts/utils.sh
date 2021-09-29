#!/usr/bin/env bash
# shellcheck disable=SC2034
## NOTE disabling all SC2034 since many of the variables defiend in this script are used externally

readonly PACKAGE_NAME='ibm-sample-panamax'
readonly BUNDLE_IMG="${PACKAGE_NAME}-bundle"
readonly _TARGET_REG="cp.stg.icr.io/cp"
readonly _CHANNELS='beta'
readonly _DEFAULT_CHANNEL='beta'
readonly _INDEX_IMG="${PACKAGE_NAME}-index"
readonly _INDEX_IMG_VERSION='latest'

OPM_TOOL='opm'
CONTAINER_TOOL='docker'
BASE_MANIFESTS_DIR="deploy/olm-catalog/${PACKAGE_NAME}"
FINAL_BASE_IMG=''
TARGET_REG=''
CHANNELS=''
DEFAULT_CHANNEL=''
VERSIONS_CSV=''
TMP_DIR=''
DEBUG=0
OPM_DEBUG_FLAG=''
OSDK_DEBUG_FLAG=''
POSITIONAL=()
VERSIONS_CSV_ARRAY=()

utils::push_image(){
    local img=$1
    local container_tool=$2

    if [ -z "${container_tool}" ]; then
      container_tool="${CONTAINER_TOOL}"
    fi

    # Workaround for https://github.com/containers/image/issues/733
    if [ "${container_tool}" == "podman" ]; then
        rm -f /var/lib/containers/cache/blob-info-cache-v1.boltdb
        rm -f "$HOME/.local/share/containers/cache/blob-info-cache-v1.boltdb"
    fi

    echo "------------ pushing via ${container_tool} push ${img} ------------ "
    ${container_tool} push "${img}"
    echo "------------"
    echo " pushed image: ${img}"
    echo " digest: $(utils::get_digest "${img}")"
    echo "------------"
}

utils::pull_image(){
    local img=$1
    local container_tool=$2

    if [ -z "${container_tool}" ]; then
      container_tool="${CONTAINER_TOOL}"
    fi

    echo "------------ pulling via ${container_tool} pull copy ${img} ------------ "
    ${container_tool} pull "${img}"
}

utils::parse_deploy_dir() {
    local base_dir=${1}
    local channels=${2}
    local defaultchannel=${3}
    local bundle_directories=("${base_dir}"/*/)

    for d in "${bundle_directories[@]}"; do
        v=$( basename "${d}")
        VERSIONS_CSV_ARRAY+=( "${v},${d},${CHANNELS},${DEFAULT_CHANNEL}" )
    done
}

utils::parse_versions_csv(){
    local csvfile="${1}"
    {
        read -r
        while IFS=, read -r version replaces skipranges operandversions defaultchannel channels description
        do
            version=$(normalize_input "$version")

            # ignore lines starting with '#'
            if [[ $version == \#* ]]; then
                continue
            fi

            defaultchannel=$(normalize_input "$defaultchannel")
            channels=$(normalize_input "$channels")

            dir="${BASE_MANIFESTS_DIR}/${version}"

            VERSIONS_CSV_ARRAY+=( "${version},${dir},${channels},${defaultchannel}" )
        done
    } < "${csvfile}"
}

utils::index_image_exists(){

    local img=$1

    if skopeo inspect docker://"${img}" --raw ; then
        return 0
    fi
    return 1
}

utils::get_digest(){
    local img=$1
    local os=${2:-linux}

    if [ -z "${CP_CREDS+x}" ]; then
        echo "CP_CREDS must be set to retrieve the image digest after push. Skipping the digest retrieval."
        return
    fi

    if ! command -v skopeo >/dev/null 2>&1; then
        echo "skopeo is not installed so unable to get sha for '${img}'"
        return
    fi

    local digest
    digest=$(skopeo --override-os "${os}" inspect docker://"${img}" --creds "${CP_CREDS}" | jq -r .Digest)

    if [ -z "${digest}" ]; then
        utils::err_exit "failed to get sha for '${img}'"
    fi
    echo "${digest}"
}

utils::create_tmpdir() {
    # print_only is a flag (whose value does not matter) to ensure only the directory is output but not created
    # This is useful for obtaining a "unique" value that you might use on a remote system
    local print_only=$1
    if [ -n "${print_only}" ]; then
        TMP_DIR=$(mktemp -d -u /tmp/XXXXXXX )
        echo "${TMP_DIR}"
    else
        TMP_DIR=$(mktemp -d /tmp/XXXXXXX )
        echo "created temp working dir ${TMP_DIR}"
    fi
}

utils::check_dependencies(){
    utils::check_skopeo
    utils::check_jq
    utils::check_operatorsdk
}

utils::check_skopeo(){
    command -v skopeo >/dev/null 2>&1 || utils::err_exit "skopeo is required but it's not installed.  Aborting."
}

utils::check_jq(){
    command -v jq > /dev/null 2>&1 || utils::err_exit "jq is required but it's not installed.  Aborting."
}

utils::check_yq(){
    command -v yq > /dev/null 2>&1 || utils::err_exit "yq is required but it's not installed.  Aborting."
}

utils::check_operatorsdk(){
    command -v operator-sdk > /dev/null 2>&1 || utils::err_exit "operator-sdk is required but it's not installed.  Aborting."
}

utils::check_containertool(){
    local container_tool=$1
    if [ -z "${container_tool}" ]; then
      container_tool="${CONTAINER_TOOL}"
    fi
    command -v "${container_tool}" > /dev/null 2>&1 || utils::err_exit "${container_tool} is required but it's not installed.  Aborting."
}


utils::check_opm(){
    command -v "${OPM_TOOL}" > /dev/null 2>&1 || utils::err_exit "${OPM_TOOL} is required but it's not installed.  Aborting."
}

utils::cleanup(){
    echo "removing dir ${TMP_DIR}"
    rm -rf "${TMP_DIR}"
}

utils::err_exit(){
    echo >&2 "[ERROR] $1"
    utils::cleanup
    exit 1
}

utils::err_exit_no_cleanup(){
    echo >&2 "[ERROR] $1"
    exit 1
}

utils::enable_debug(){
    OPM_DEBUG_FLAG='--debug'
    OSDK_DEBUG_FLAG='--verbose'
}

normalize_input(){
    local temp=$1

    # remove quotes
    temp="$(echo -e "${temp}" | tr -d '[:space:]')"
    temp="${temp%\"}"
    temp="${temp#\"}"
    echo "$temp"
}