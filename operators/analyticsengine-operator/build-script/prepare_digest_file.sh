#!/bin/bash
echo "========================="
echo "Prepare component images to digests.yaml for Analytics Engine Operator build"
echo "========================="

if ! bash ${TRAVIS_BUILD_DIR}/build-script/trigger_bundle_build_check.sh; then
  echo "Skipped stage"
  exit 0
fi

echo $TRAVIS_OS_NAME
echo $TRAVIS_ARCH

echo "Install pip3 install yq"
pip3 install yq

echo "Login Docker Registry"
docker login -u $DOCKER_USERNAME -p $DOCKER_API_KEY $DOCKER_REGISTRY

echo "Getting all the image and convert tag to digest"
casectl plugin update-image-digests --csv $OPERATOR_PATH/build-script/images.csv -c $OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/ --overwrite -v 2

echo "Generate digest.yaml from the resource.yaml"
export RESOURCE_YAML_FILE=$OPERATOR_BUNDLE_PATH/stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/inventory/analyticsengineOperatorSetup/resources.yaml
export DIGEST_FILE=$OPERATOR_PATH/playbooks/vars/digests.yaml

echo "RESOURCE_YAML_FILE"
cat $RESOURCE_YAML_FILE
cat $RESOURCE_YAML_FILE | yq '.resources.resourceDefs.containerImages' | jq '{ "image_digests" : map( { ((if (.platform.architecture|tostring) != "null" then (((.image|tostring) + "-" + (.platform.architecture|tostring))) else (.image|tostring) end)): .digest } ) | add , "image_tags" : map( { (.image|tostring): .tag } ) | add }' > $DIGEST_FILE
yq -i -y . $DIGEST_FILE
echo "DIGEST_FILE"
cat $DIGEST_FILE

# Save the digests.yaml file to bundle repo to use accoss the Travis build stage (This is a walkaround since Enterprise Travis have not support workspaces)
echo "Update digests.yaml to operator bundle repository"
yes | cp -rf $DIGEST_FILE $OPERATOR_BUNDLE_PATH/

echo "==================== Debuggers ====================="
ls -lrt $OPERATOR_BUNDLE_PATH/
cd $OPERATOR_BUNDLE_PATH
pwd
ls -lrt
echo "==================== Debuggers END ====================="
git commit -am "Build $TRAVIS_BUILD_NUMBER - Update digests.yaml from automated analyticsengine-operator travis commit"
git push -u origin master