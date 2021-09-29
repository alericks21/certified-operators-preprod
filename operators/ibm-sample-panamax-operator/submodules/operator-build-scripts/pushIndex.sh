#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

# imports
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

TARGET_REG="${1:-$_TARGET_REG}"
INDEX_IMG="${2:-$_INDEX_IMG}"
# We expect the architecture to be provided with {arch} template
INDEX_IMG_VERSION_TEMPLATE="${3}"
CONTAINER_TOOL="${4:-docker}"

if [ -z "${INDEX_IMG_VERSION_TEMPLATE+x}" ]; then
  utils::err_exit_no_cleanup "The index image template must be set. Aborting."
fi

utils::check_containertool "${CONTAINER_TOOL}"

declare -A ArchLookup
ArchLookup=([x86_64]=amd64 [ppc64le]=ppc64le [s390x]=s390x)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

PROCESSED_MANIFEST_IMAGE="${INDEX_IMG_VERSION_TEMPLATE/\{os\}/${OS}}"
PROCESSED_MANIFEST_IMAGE="${PROCESSED_MANIFEST_IMAGE/\{arch\}/${ArchLookup[$(uname -i)]}}"

# replace the {arch} template with the actual architecture
img="${TARGET_REG}/${INDEX_IMG}:${PROCESSED_MANIFEST_IMAGE}"

utils::push_image "${img}" "${CONTAINER_TOOL}"

exit 0