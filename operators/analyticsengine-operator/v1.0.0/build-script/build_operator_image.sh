#!/bin/bash
echo "========================="
echo "Build Analytics Engine Operator Image for $1"
echo "========================="

if ! bash +x ${TRAVIS_BUILD_DIR}/build-script/trigger_bundle_build_check.sh; then
  echo "Skip stage"
  exit 0
fi

echo $TRAVIS_OS_NAME
echo $TRAVIS_ARCH
echo "arch: $1"

echo "Login Docker Registry"
docker login -u $DOCKER_USERNAME -p $DOCKER_API_KEY $DOCKER_REGISTRY
docker login -u ${REDHAT_USERNAME} -p ${REDHAT_PASSWORD} ${REDHAT_REGISTRY}

export DIGEST_FILE=$OPERATOR_BUNDLE_PATH/digests.yaml
echo "DIGEST_FILE"
cat $DIGEST_FILE

#Update appVersion in main.yaml in deafult directory
export CASE_VERSION=4.0.1-$TRAVIS_BUILD_NUMBER
sed -i "s|CHANGE_ME_APPVERSION|$CASE_VERSION|g" $OPERATOR_PATH/roles/analyticsengine/defaults/main.yml
sed -i "s|BUILD_NUMBER|$CASE_VERSION|g" $OPERATOR_PATH/Dockerfile

cat $OPERATOR_PATH/roles/analyticsengine/defaults/main.yml

yes | cp -rf $DIGEST_FILE $OPERATOR_PATH/playbooks/vars/

sed -i "s|BUILD_NUMBER|$TRAVIS_BUILD_NUMBER|g" $OPERATOR_PATH/playbooks/vars/digests.yaml

echo "Build analyticsengine-operator image"
export VERSION=1.0.${TRAVIS_BUILD_NUMBER}
make docker-build docker-push IMG=$DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator:$VERSION-$TRAVIS_ARCH BUILD_ARGS="--build-arg ARCH=$TRAVIS_ARCH" VERSION=$VERSION-$TRAVIS_ARCH

echo "Get newly pushed operator digest"
if [[ $TRAVIS_ARCH == "amd64" ]] ; then
    export OPERATOR_DIGEST_AMD64=$(docker images --digests | grep "$VERSION-$TRAVIS_ARCH" | awk '{print $3}')
    echo $OPERATOR_DIGEST_AMD64
else 
    export OPERATOR_DIGEST_POWER=$(docker images --digests | grep "$VERSION-$TRAVIS_ARCH" | awk '{print $3}')
    echo $OPERATOR_DIGEST_POWER
fi