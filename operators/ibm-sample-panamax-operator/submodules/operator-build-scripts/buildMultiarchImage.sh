#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# imports
# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
# shellcheck source=utils.sh
source "${SCRIPT_DIR}/utils.sh"

## Globals

## Functions

usage() {
  echo -n "$(basename "$0") [OPTION]...

Build a multiarch operator controller image

 Options:
  -a, --architectures      Comma-seperated list of architectures to build for (default 'amd64')
  -c, --container-tool     Tool to build image [docker, podman] (default 'docker')
  -i, --image-name         What to name the image being built (such as docker.io/ibmcom/ibm-sample-panamax-operator) (required)
  -t, --tag                Tag for the multiarch image (required)
  -f, --docker-file        Dockerfile to use (default 'Dockerfile')
  -p, --push               If present, will push to the repo
  -h, --help               Display this help text

"
exit 0
}

ARCHITECTURES="amd64"
BUILD_IMG_NAME=""
TAG=""
DOCKERFILE="Dockerfile"
PUSH=0

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -a|--architectures)
    ARCHITECTURES="$2"
    shift 2
    ;;
    -c|--container-tool)
    CONTAINER_TOOL="$2"
    shift 2
    ;;
    -i|--image-name)
    BUILD_IMG_NAME="$2"
    shift 2
    ;;
    -t|--tag)
    TAG="$2"
    shift 2
    ;;
    -f|--docker-file)
    DOCKERFILE="$2"
    shift 2
    ;;
    -p|--push)
    PUSH=1
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

if [[ -z "${ARCHITECTURES}" ]]; then
  ARCHITECTURES="amd64"
fi

if [[ -z "${CONTAINER_TOOL}" ]]; then
  CONTAINER_TOOL="docker"
fi

if [[ -z "${BUILD_IMG_NAME}" ]]; then
  utils::err_exit_no_cleanup "--image-name argument is required"
fi

if [[ -z "${TAG}" ]]; then
  utils::err_exit_no_cleanup "--tag argument is required"
fi

if [[ -z "${DOCKERFILE}" ]]; then
  DOCKERFILE="Dockerfile"
fi

if [[ -z "${PUSH}" ]]; then
  PUSH=0
fi

IFS=',' read -ra archs <<< "${ARCHITECTURES}"
for a in "${archs[@]}"; do
  docker build . -t "${BUILD_IMG_NAME}:${TAG}-linux.${a}" -f "${DOCKERFILE}" --build-arg "arch=${a}" --build-arg "token=${GITHUB_TOKEN}" --build-arg "user=${GITHUB_USER}"
  if [[ "${PUSH}" -eq 1 ]]; then
    utils::push_image "${BUILD_IMG_NAME}:${TAG}-linux.${a}" "${CONTAINER_TOOL}"
  fi
done

"${SCRIPT_DIR}/buildManifest.sh" --image-name-base "${BUILD_IMG_NAME}:${TAG}" --image-name-template '{base}-{os}.{arch}' --platforms "${ARCHITECTURES}" --container-tool "${CONTAINER_TOOL}"

if [[ "${PUSH}" -eq 1 ]]; then
  ${CONTAINER_TOOL} manifest push "${BUILD_IMG_NAME}:${TAG}"
fi

exit 0