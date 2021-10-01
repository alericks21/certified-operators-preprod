#!/bin/bash
set -x
echo "========================="
echo "Build Analytics Engine Operator fat manifest, Analytics Engine Operator Bundle and Catalogs"
echo "========================="

if ! bash ${TRAVIS_BUILD_DIR}/build-script/trigger_bundle_build_check.sh; then
  echo "Skip stage"
  exit 0
fi

CATALOG_BASE_IMAGE=ose-operator-registry
CATALOG_BASE_IMAGE_TAG=v4.7

echo "Install skopeo podman"
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_18.04/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_18.04/Release.key | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install skopeo podman
	
echo "Login Docker Registry"
# Need the flag --authfile= to save the config.json for the "casectl plugin update-image-digests" command
podman  login --authfile=${HOME}/.docker/config.json -u $DOCKER_USERNAME -p $DOCKER_API_KEY $DOCKER_REGISTRY

echo "Install upstream opm"
wget https://github.com/operator-framework/operator-registry/releases/download/v1.15.1/linux-amd64-opm
mv linux-amd64-opm opm
chmod +x opm && sudo cp opm /usr/local/bin/
export PATH=$PATH:${TRAVIS_BUILD_DIR}/opm

echo "Install operator-sdk"
export ARCH=$(case $(arch) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(arch) ;; esac)
export OS=$(uname | awk '{print tolower($0)}')
export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.4.2
curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}
chmod +x operator-sdk_${OS}_${ARCH} && sudo mv operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk-1.4

export IMAGE_NAME=ibm-cpd-analyticsengine-operator
export VERSION=1.0.${TRAVIS_BUILD_NUMBER}
export CASE_VERSION=4.0.1-$TRAVIS_BUILD_NUMBER
export OPERATOR_BUNDLE_OLD_GMC_TAG=1.0.245
echo "Pull the operator image for amd64 and ppc64le"
podman pull $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}-amd64
podman pull $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}-ppc64le

echo "Get new docker version, enable experimental"
cat <<< $(jq '.+{"experimental":"enabled"}' ~/.docker/config.json) > ~/.docker/config.json

echo "Build fat manifest"
docker manifest create $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}  $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}-amd64 $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}-ppc64le
docker manifest annotate $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION} $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}-amd64  --os linux --arch amd64 
docker manifest annotate $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}  $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}-ppc64le --os linux --arch ppc64le 
docker manifest inspect $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}
docker manifest push $DOCKER_REGISTRY/$IMAGE_NAME:${VERSION}

docker images --digests
export OPERATOR_DIGEST_MANIFEST=$(skopeo inspect docker://$DOCKER_REGISTRY/$IMAGE_NAME:${VERSION} |jq -r ".Digest")
echo "Operator Digest Manifest Digests: $OPERATOR_DIGEST_MANIFEST"

echo "Bundle analyticsengine operator, Validate analyticsengine bundle"
#sed -i "s#image: $PARTITION_COLUMN.*#image: icr.io/cpopen/ibm-cpd-analyticsengine-operator@$OPERATOR_DIGEST_MANIFEST#" $TRAVIS_BUILD_DIR/bundle/manifests/analyticsengine_operator_service_account.yaml
sed -i "s#image: $PARTITION_COLUMN.*#image: icr.io/cpopen/ibm-cpd-analyticsengine-operator@$OPERATOR_DIGEST_MANIFEST#" $TRAVIS_BUILD_DIR/bundle/manifests/ibm-cpd-ae-operator.clusterserviceversion.yaml
sed -i "s#BUILD_NUMBER#${CASE_VERSION}#g" $TRAVIS_BUILD_DIR/bundle/manifests/ibm-cpd-ae-operator.clusterserviceversion.yaml

sed -i "s#BUILD_NUMBER#${CASE_VERSION}#g" $TRAVIS_BUILD_DIR/bundle.Dockerfile
sed -i "s#BUILD_NUMBER#${CASE_VERSION}#g" $TRAVIS_BUILD_DIR/catalog.Dockerfile
# make bundle IMG=$DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator@$OPERATOR_DIGEST_MANIFEST CHANNELS=1.0.0 DEFAULT_CHANNEL=1.0.0 OPERATOR_SDK=operator-sdk-1.4 VERSION=$VERSION

echo "Build analyticsengine-operator-bundle image"
make bundle-build docker-push-bundle BUNDLE_IMG=$DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:$VERSION VERSION=$VERSION

echo "Get analyticsengine-operator-bundle digest and create ibm-cpd-analyticsengine-operator-catalog"
podman pull $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:$VERSION
podman images --digests --noheading $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:$VERSION
OPERATOR_BUNDLE_DIGEST=$(podman images --digests --noheading $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:$VERSION | awk '{print $3}')

echo "Get old GMC analyticsengine-operator-bundle digest and create ibm-cpd-analyticsengine-operator-catalog"
podman pull $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:$OPERATOR_BUNDLE_OLD_GMC_TAG
podman images --digests --noheading $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:$OPERATOR_BUNDLE_OLD_GMC_TAG
OPERATOR_BUNDLE_400_DIGEST=$(podman images --digests --noheading $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle:$OPERATOR_BUNDLE_OLD_GMC_TAG | awk '{print $3}')

if [[ "$ARCH" != "x86_64" ]];then
    podman login -u ${REDHAT_USERNAME} -p ${REDHAT_PASSWORD} ${REDHAT_REGISTRY}/${CATALOG_BASE_IMAGE}:${CATALOG_BASE_IMAGE_TAG}
    base_image_opt=" --binary-image ${REDHAT_REGISTRY}/${CATALOG_BASE_IMAGE}:${CATALOG_BASE_IMAGE_TAG}"
fi

#${TRAVIS_BUILD_DIR}/opm index add ${base_image_opt} --bundles $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle@$OPERATOR_BUNDLE_DIGEST --tag $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:$VERSION --build-tool=docker

echo
echo "Remove database directory generated by previous build"

pwd
rm -rf database
rm -rf bundles.db

## New catalog image creation code
${TRAVIS_BUILD_DIR}/opm registry add --bundle-images $PRODUCTION_DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle@$OPERATOR_BUNDLE_400_DIGEST,$PRODUCTION_DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-bundle@$OPERATOR_BUNDLE_DIGEST --container-tool podman
podman build -f catalog.Dockerfile --format docker . -t $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:$VERSION

if [[ $? -ne 0 ]]; then
    echo "Command \"podman build -f catalog.Dockerfile  --format docker . -t $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:$VERSION\" failed"
    exit 1
fi

echo "Push analyticsengine-operator-catalog"
podman push --format v2s2 $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:$VERSION
podman tag $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:$VERSION $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:1.0.0
podman push --format v2s2 $DOCKER_REGISTRY/ibm-cpd-analyticsengine-operator-catalog:1.0.0