#!/bin/bash
echo "========================="
echo "Prepare the case bundle zip file"
echo "========================="

if ! bash ${TRAVIS_BUILD_DIR}/build-script/trigger_bundle_build_check.sh; then
  echo "Skip stage"
  exit 0
fi

echo "Install pip3 install yq"
pip3 install yq

echo "Install skopeo podman"
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_18.04/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_18.04/Release.key | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install skopeo podman

echo "Login Docker Registry"
# Need the flag --authfile= to save the config.json for the "casectl plugin update-image-digests" command
podman login --authfile=${HOME}/.docker/config.json -u $DOCKER_USERNAME -p $DOCKER_API_KEY $DOCKER_REGISTRY

export CPD_VERSION=4.0.1
export CASE_VERSION=$CPD_VERSION-$TRAVIS_BUILD_NUMBER
export RESOURCE_YAML_FILE=$OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/resources.yaml
export VERSION=1.0.${TRAVIS_BUILD_NUMBER}
export IMAGE_NAME=ibm-cpd-analyticsengine-operator


podman pull $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator:${VERSION}
podman pull $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:${VERSION}
podman pull $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:${VERSION}
export OPERATOR_DIGEST_MANIFEST=$(skopeo inspect docker://$DOCKER_REGISTRY/$IMAGE_NAME:${VERSION} |jq -r ".Digest")
export OPERATOR_BUNDLE_DIGEST=$(podman images --digests | grep 'ibm-cpd-analyticsengine-operator-bundle' | awk '{print $3}')
export OPERATOR_CATALOG_DIGEST=$(podman images --digests | grep 'ibm-cpd-analyticsengine-operator-catalog' | awk '{print $3}')
echo "Operator Digest Manifest Digests: $OPERATOR_DIGEST_MANIFEST"

cd $OPERATOR_BUNDLE_PATH
echo "Update submodule"
git submodule update --recursive --remote

echo "Add analyticsengine-operator, ibm-analyticsengine-bundle to images.csv and generate resource.yaml again"
sed -i "s#ibm-cpd-analyticsengine-operator,1.0.0,sha256:\([a-zA-Z0-9]*\),#ibm-cpd-analyticsengine-operator,$VERSION,$OPERATOR_DIGEST_MANIFEST,#g" ${TRAVIS_BUILD_DIR}/build-script/images.csv
sed -i "s#ibm-cpd-analyticsengine-operator-bundle,1.0.0,sha256:\([a-zA-Z0-9]*\),#ibm-cpd-analyticsengine-operator-bundle,$VERSION,$OPERATOR_BUNDLE_DIGEST,#g" ${TRAVIS_BUILD_DIR}/build-script/images.csv
sed -i "s#ibm-cpd-analyticsengine-operator-catalog,1.0.0,sha256:\([a-zA-Z0-9]*\),#ibm-cpd-analyticsengine-operator-catalog,$VERSION,$OPERATOR_CATALOG_DIGEST,#g" ${TRAVIS_BUILD_DIR}/build-script/images.csv

casectl plugin update-image-digests --csv ${TRAVIS_BUILD_DIR}/build-script/images.csv -c $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/ --overwrite -v 2
echo "RESOURCE_YAML_FILE"
cat $RESOURCE_YAML_FILE

echo "Add required metadata to operator-bundle and update resgitry to icr.io/cpopen"
cat $RESOURCE_YAML_FILE | yq . | jq '.resources.resourceDefs.containerImages | map(if .image == "cp/ibm-cpd-analyticsengine-operator" then .image = "cpopen/ibm-cpd-analyticsengine-operator" else . end)' | jq 'map(if .image == "cp/ibm-cpd-analyticsengine-operator-catalog" then .image = "cpopen/ibm-cpd-analyticsengine-operator-catalog" else . end)'| jq 'map(if .image == "cp/ibm-cpd-analyticsengine-operator-bundle" then .image = "cpopen/ibm-cpd-analyticsengine-operator-bundle" else . end)' | jq --argjson json '{"operators_operatorframework_io":{"bundle":{"cpcicd_ibm_com":{"targetCatalogs":{"catalogRefs":[{"ibm-public":{}}]}},"mediaType":"registry+v1"}}}' 'map(if .image | contains( "ibm-cpd-analyticsengine-operator-bundle") then .metadata = $json else . end)' | jq --argjson json '{"operators_operatorframework_io":{"catalog":{"mediaType":"registry+v1"}}}' 'map(if .image | contains("ibm-cpd-analyticsengine-operator-catalog") then .metadata = $json else . end)'  | jq --argjson json '[{"host":"icr.io"}]' '. | map(if ((.image | contains("ibm-cpd-analyticsengine-operator")) or (.image | contains("ibm-cpd-analyticsengine-operator-bundle")) or (.image | contains("ibm-cpd-analyticsengine-operator-catalog"))) then .registries = $json else . end)' > TEMP1.tmp
cat $RESOURCE_YAML_FILE | yq . | jq --argjson json "$(cat TEMP1.tmp)" '.resources.resourceDefs.containerImages = $json' > TEMP2.tmp
# cat $RESOURCE_YAML_FILE | yq . | jq --slurpfile json TEMP1.tmp '.resources.resourceDefs.containerImages = $json' > TEMP2.tmp
mv TEMP2.tmp $RESOURCE_YAML_FILE
yq -i -y . $RESOURCE_YAML_FILE
echo "resource.yaml with bundle digest and required field"
cat $RESOURCE_YAML_FILE

#copy deploy directory to case bundle directory
rm -rf $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/files/deploy
cp -r $TRAVIS_BUILD_DIR/deploy $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/files/

if [[ $GMC_PUSH == "true" ]]
then
    BUNDLE_VERSION=$CPD_VERSION
else
    BUNDLE_VERSION=$CASE_VERSION
fi

echo "Update docker repo to cp.icr.io/cp/cpd to fix lint issue. For later we can use skopeo to copy image to retain digest, for local testing create the mirror in the target repo"
sed -i "s#cp.stg.icr.io#cp.icr.io#g" $RESOURCE_YAML_FILE
sed -i "s/appVersion: $PARTITION_COLUMN.*/appVersion: ${BUNDLE_VERSION}/" $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/case.yaml
sed -i "s/version: $PARTITION_COLUMN.*/version: ${BUNDLE_VERSION}/" $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/case.yaml
sed -i "s#image: $PARTITION_COLUMN.*#image: icr.io/cpopen/ibm-cpd-analyticsengine-operator@$OPERATOR_DIGEST_MANIFEST#" $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/files/deploy/operator.yaml
sed -i "s#image: $PARTITION_COLUMN.*#image: icr.io/cpopen/ibm-cpd-analyticsengine-operator@$OPERATOR_DIGEST_MANIFEST#" $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/files/deploy/olm-catalog/ibm-cpd-ae-operator/1.0.0/ibm-cpd-ae-operator.clusterserviceversion.yaml
sed -i "s#image: $PARTITION_COLUMN.*#image: icr.io/cpopen/ibm-cpd-analyticsengine-operator-catalog@$OPERATOR_CATALOG_DIGEST#" $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/files/deploy/install/catalog-source.yaml
sed -i "s#BUILD_NUMBER#${CASE_VERSION}#" $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/files/deploy/olm-catalog/ibm-cpd-ae-operator/1.0.0/ibm-cpd-ae-operator.clusterserviceversion.yaml
echo "resource.yaml with hardcoded repository for lint error"
cat $RESOURCE_YAML_FILE

echo "Prepare the case only folder up the case bundle folder"
cp -Lr $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine ${TRAVIS_BUILD_DIR}/

echo "Build $TRAVIS_BUILD_NUMBER - Merge from master, update submodule and resource.yaml from automated analyticsengine-operator travis commit"
git add $OPERATOR_BUNDLE_PATH/.
git commit -am "Build $TRAVIS_BUILD_NUMBER - Update submodule and resource.yaml from automated analyticsengine-operator travis commit"
git pull origin master
git push -u origin master

echo "Zip all the case bundle"
tar zcvf ibm-analyticsengine-${BUNDLE_VERSION}.tgz -C ${TRAVIS_BUILD_DIR} ibm-analyticsengine

echo "Distribute case bundle to icpfs local folder"
sshpass -p $FILE_SERVER_KEY ssh -o StrictHostKeyChecking=no -tt build@icpfs1.svl.ibm.com mkdir -p /pool1/data1/zen/cp4d-builds/$CPD_VERSION/local/components/analyticsengine/case/${TRAVIS_BUILD_NUMBER}
sshpass -p $FILE_SERVER_KEY scp -r ibm-analyticsengine-${BUNDLE_VERSION}.tgz build@icpfs1.svl.ibm.com:/pool1/data1/zen/cp4d-builds/$CPD_VERSION/local/components/analyticsengine/case/${TRAVIS_BUILD_NUMBER}
sshpass -p $FILE_SERVER_KEY ssh -o StrictHostKeyChecking=no -tt build@icpfs1.svl.ibm.com ln -sfn /pool1/data1/zen/cp4d-builds/$CPD_VERSION/local/components/analyticsengine/case/${TRAVIS_BUILD_NUMBER} /pool1/data1/zen/cp4d-builds/$CPD_VERSION/local/components/analyticsengine/case/latest

echo "Distribute case bundle to icpfs dev folder"
sshpass -p $FILE_SERVER_KEY ssh -o StrictHostKeyChecking=no -tt build@icpfs1.svl.ibm.com mkdir -p /pool1/data1/zen/cp4d-builds/$CPD_VERSION/dev/components/analyticsengine/case/${TRAVIS_BUILD_NUMBER}
sshpass -p $FILE_SERVER_KEY scp -r ibm-analyticsengine-${BUNDLE_VERSION}.tgz build@icpfs1.svl.ibm.com:/pool1/data1/zen/cp4d-builds/$CPD_VERSION/dev/components/analyticsengine/case/${TRAVIS_BUILD_NUMBER}
sshpass -p $FILE_SERVER_KEY ssh -o StrictHostKeyChecking=no -tt build@icpfs1.svl.ibm.com ln -sfn /pool1/data1/zen/cp4d-builds/$CPD_VERSION/dev/components/analyticsengine/case/${TRAVIS_BUILD_NUMBER} /pool1/data1/zen/cp4d-builds/$CPD_VERSION/dev/components/analyticsengine/case/latest

echo "Update ibm-analyticsengine case in Git repository"

casectl repo update -a ibm-analyticsengine-${BUNDLE_VERSION}.tgz -r ${AE_CASE_PATH}/dev/case-repo-dev
#casectl repo update -a ibm-analyticsengine-${BUNDLE_VERSION}.tgz -r ${AE_CASE_PATH}/local/case-repo-local
echo "Copy the sample CR"
mkdir -p ${AE_CASE_PATH}/cr/analyticsengine
yes | cp -rf ${TRAVIS_BUILD_DIR}/deploy/crds/ae_v1_analyticsengine_cr.yaml ${AE_CASE_PATH}/cr/analyticsengine/cr.yaml
cd $AE_CASE_PATH
git add ${AE_CASE_PATH}/.
git commit -am "Build $TRAVIS_BUILD_NUMBER - Automation to update ibm-analyticsengine case"
git push -u origin $CASE_BRANCH_OVERRIDE
