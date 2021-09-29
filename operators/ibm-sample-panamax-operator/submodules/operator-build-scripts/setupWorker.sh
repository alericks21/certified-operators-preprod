#!/usr/bin/env bash


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# some scripts need to be here so set this directory up
mkdir -p "${SCRIPT_DIR}"/library


# An .env file can be used to pass along sensitive environment vars used in this script.
# The .env file should be copied along with this script onto a remote machine.
# We immediatly removes the env file after sourcing to cleanup
# shellcheck source=.env
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env" && rm "${SCRIPT_DIR}/.env"

# download & execute the script that gets dependencies
wget -O "${SCRIPT_DIR}"/catalogInstallDependencies.sh --auth-no-challenge --header="Accept: application/vnd.github.raw" --http-user="${GITHUB_USER}" --http-password="${GITHUB_TOKEN}" https://raw.github.ibm.com/IBMPrivateCloud/content-tools/master/travis-tools/catalog/bin/catalogInstallDependencies.sh
wget -O "${SCRIPT_DIR}"/setupOC.sh --auth-no-challenge --header="Accept: application/vnd.github.raw" --http-user="${GITHUB_USER}" --http-password="${GITHUB_TOKEN}" https://raw.github.ibm.com/IBMPrivateCloud/content-tools/master/library/setupOC.sh
wget -O "${SCRIPT_DIR}"/library/utilities.sh --auth-no-challenge --header="Accept: application/vnd.github.raw" --http-user="${GITHUB_USER}" --http-password="${GITHUB_TOKEN}" https://raw.github.ibm.com/IBMPrivateCloud/content-tools/master/library/utilities.sh

# shellcheck disable=SC2034
toolrepositoryroot="${SCRIPT_DIR}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}"/catalogInstallDependencies.sh
# shellcheck source=/dev/null
source "${SCRIPT_DIR}"/setupOC.sh
# shellcheck source=/dev/null
source "${SCRIPT_DIR}"/library/utilities.sh

# pupdate() { case ":${PATH:=$1}:" in *:"$1":*) ;; *) PATH="$1:$PATH" ;; esac; }

# if docker is not installed, then go get it
docker version || wget -qO- https://get.docker.com/ | sh

jq --version || apt-get update -qq && apt-get -qq --assume-yes install jq
pass --version || apt-get update -qq && apt-get -qq --assume-yes install pass
make --version || apt-get update -qq && apt-get -qq --assume-yes install make
apt-get -qq --assume-yes install build-essential pkg-config libsecret-1-dev
# NOTE: the latest version of go is inconsistent and old using apt-get
#       go --version || apt-get update -qq && apt-get -qq --assume-yes install golang-go
#       Just downlaod the latest binary instead and dump it into /usr/local
declare -A ArchLookup
ArchLookup=([x86_64]=amd64 [ppc64le]=ppc64le [s390x]=s390x)
/usr/local/go/bin/go version || curl -L "https://dl.google.com/go/$(curl -s https://golang.org/dl/?mode=json | jq -r .[0].version).linux-${ArchLookup[$(uname -i)]}.tar.gz" | tar xvz --directory /usr/local

# force the profile to be loaded
# shellcheck disable=SC1091
# source "/root/.profile"
# shellcheck disable=SC1091
grep /usr/local/go/bin /etc/environment > /dev/null || if [ -f /etc/environment ]; then echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go" >> /etc/environment; source "/etc/environment"; fi
# shellcheck disable=SC1091
grep GOPATH /etc/environment > /dev/null || if [ -f /etc/environment ]; then echo "export GOPATH=$HOME/go" >> /etc/environment; source "/etc/environment"; fi

# file is does not usually exist, so create it always, and then append the next line
echo "default-cache-ttl 34560000" > "$HOME/.gnupg/gpg-agent.conf"
echo "max-cache-ttl 34560000" >> "$HOME/.gnupg/gpg-agent.conf"

# install docker-credential-pass (either pre-built or built from source)
if [[ "$(uname -i)" == "x86_64" ]]; then
    docker-credential-pass version || curl -L "$(curl -s https://api.github.com/repos/docker/docker-credential-helpers/releases/latest | jq -r '.assets[] | select(.browser_download_url | contains("docker-credential-pass")) | .browser_download_url')" | tar xvz --directory /usr/local/bin && chmod 755 /usr/local/bin/docker-credential-pass
else
    docker-credential-pass version || go get -u github.com/docker/docker-credential-helpers/... && cd "$GOPATH/src/github.com/docker/docker-credential-helpers" && make pass && cp "$GOPATH/src/github.com/docker/docker-credential-helpers/bin/docker-credential-pass" /usr/local/bin
fi

# make sure that the experimental flag is set and restart docker
DAEMON_JSON=/etc/docker/daemon.json
if [[ ! -f "${DAEMON_JSON}" ]]; then
    echo "{}" > "${DAEMON_JSON}"
fi
jq '.experimental = true' "${DAEMON_JSON}" > "${DAEMON_JSON}.tmp" && mv "${DAEMON_JSON}.tmp" "${DAEMON_JSON}"
systemctl restart docker
# make sure client docker experimental flag is set
CLI_DOCKER_HOME=${HOME}/.docker
CLI_DOCKER_JSON=${CLI_DOCKER_HOME}/config.json
mkdir -p "${CLI_DOCKER_HOME}"
if [[ ! -f "${CLI_DOCKER_JSON}" ]]; then
    echo "{}" > "${CLI_DOCKER_JSON}"
fi
jq '(.experimental = "enabled" | .credsStore = "pass")' "${CLI_DOCKER_JSON}" > "${CLI_DOCKER_JSON}.tmp" && mv "${CLI_DOCKER_JSON}.tmp" "${CLI_DOCKER_JSON}"


# currently the tools are only ever going to work on x86_64, but setup for the future
if [[ "$(uname -i)" == "x86_64" ]]; then
    oc version || CV_OC_VERSION_LINK=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.5.0/openshift-client-linux-4.5.0.tar.gz getOC "v4.5.0"
    opmv1.12.3d version || getOpm "v1.12.3d"
    # This version number is made up... at this time the quay v4.6 tag of image was not a tagged build of opm and therefore has no version number
    opmv1.14.0 version || CATALOG_OPM_BINARY_IMAGE="quay.io/openshift/origin-operator-registry:v4.6" getOpm "v1.14.0"
    skopeo --version || getSkopeo
    grpcurl --version || getGrpcurl
    podman --version || getPodman
    ibmcloud --version || getIbmcloud
elif [[ "$(uname -i)" == "ppc64le" ]]; then
    # commented out items don't exist for this architecture

    # oc version || CV_OC_VERSION_LINK=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.5.0/openshift-client-linux-4.5.0.tar.gz getOC "v4.5.0"
    # opmv1.12.3d version || getOpm "v1.12.3d"
    # skopeo --version || getSkopeo
    # grpcurl --version || getGrpcurl
    # podman --version || getPodman
    ibmcloud --version || getIbmcloud
elif [[ "$(uname -i)" == "s390x" ]]; then
    # currently none of the tools exist for this architecture
    :
    # oc version || CV_OC_VERSION_LINK=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.5.0/openshift-client-linux-4.5.0.tar.gz getOC "v4.5.0"
    # opmv1.12.3d version || getOpm "v1.12.3d"
    # skopeo --version || getSkopeo
    # grpcurl --version || getGrpcurl
    # podman --version || getPodman
    # ibmcloud --version || getIbmcloud
fi