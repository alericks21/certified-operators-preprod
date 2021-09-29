#!/bin/bash
set -euo pipefail

# Your final operator index image MUST have your production bundle image repo location NOT your internal testing repo!!
# There is a defect with the opm index add command that prevents it from using a local registries.conf file repo
# once this bug is fixed qwe should be able to remove this type of process

list=""
repo=${1:-docker.io/ibmcom}
index=${2:-ibm-panamax-catalog}
indexVer=${3:-latest}
container_tool=${4:-docker}
opm_tool=${5:-opm}

for directory in ./deploy/olm-catalog/ibm-sample-panamax/*/ ; do
    package=$(echo "$directory" | cut -d'/' -f4)
    ver=$(echo "$directory" | cut -d'/' -f5)
    if [ -z "$list" ]
    then
      list=$repo/$package-bundle:$ver
    else
      list=$list,$repo/$package-bundle:$ver
    fi
done
img="$repo"/"$index":"$indexVer"
echo "running --> opm index add -c ${container_tool} --bundles $list --tag ${img}"
"${opm_tool}" index add -c "${container_tool}" --bundles "$list" --tag "${img}"
echo "running -> skopeo copy docker-daemon:${img} docker://${img}"
utils::push_image "${img}" "${container_tool}"
#skopeo copy docker-daemon:"${img}" docker://"${img}" --dest-creds "$CP_CREDS"
skopeo inspect docker://"${img}" --creds="${CP_CREDS}" | jq '.Digest'