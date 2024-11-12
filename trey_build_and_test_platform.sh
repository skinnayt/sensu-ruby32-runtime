#!/bin/bash

ignore_errors=0
ruby_version=3.2.0
ruby_install_version=0.9.3
asset_version=${TAG:-local-build}

asset_filename_noarch=sensu-ruby-runtime_${asset_version}_ruby-${ruby_version}_${platform}_linux_ARCH.tar.gz
asset_image_noarch=sensu-ruby-runtime-${ruby_version}-${platform}-ARCH:${asset_version}


if [ "${asset_version}" = "local-build" ]; then
  echo "Local build"
  ignore_errors=1
fi

# Build for amd64 and arm64/aarch64
ARCHES="amd64 arm64"

for ARCH in ${ARCHES}; do
  asset_filename=$(echo ${asset_filename_noarch} | sed -e "s/ARCH/${ARCH}/")
  asset_image=$(echo ${asset_image_noarch} | sed -e "s/ARCH/${ARCH}/")
  echo -e "Platform: ${platform}\nArchitecture: ${ARCH}"
  echo "Check for asset file: ${asset_filename}"

  # Used for running under emulated architecture
  EMULARCH=""

  if [ ${ARCH} == "arm64" ]; then
    EMULARCH="-v /usr/bin/qemu-aarch64:/usr/bin/qemu-aarch64"
  fi

  if [ -f "$PWD/dist/${asset_filename}" ]; then
    echo "File: "$PWD/dist/${asset_filename}" already exists!!!"
    [ $ignore_errors -eq 0 ] && exit 1  
  else
    echo "Check for docker image: ${asset_image}"
    if [[ "$(docker image ls -q ${asset_image} 2> /dev/null)" == "" ]]; then
      echo "Docker image not found...we can build"
      echo "Building Docker Image: sensu-ruby-runtime:${ruby_version}-${platform}-${ARCH}"
      
      echo docker buildx build --builder build-trey --platform linux/${ARCH} --build-arg "BUILD_ARCH=$ARCH" --build-arg "RUBY_VERSION=$ruby_version" --build-arg "RUBY_INSTALL_VERSION=${ruby_install_version}" --build-arg "ASSET_VERSION=$asset_version" -t ${asset_image} --load -f Dockerfile.${platform} .
      docker buildx build --builder build-trey --platform linux/${ARCH} --build-arg "BUILD_ARCH=$ARCH" --build-arg "RUBY_VERSION=$ruby_version" --build-arg "RUBY_INSTALL_VERSION=${ruby_install_version}" --build-arg "ASSET_VERSION=$asset_version" -t ${asset_image} --load -f Dockerfile.${platform} .
      
      echo "Done initial build"
      echo "Making Asset: /assets/sensu-ruby-runtime_${asset_version}_ruby-${ruby_version}_${platform}_linux_${ARCH}.tar.gz"

      echo docker run --platform linux/${ARCH} ${EMULARCH} -v "$PWD/dist:/dist" ${asset_image} cp /assets/${asset_filename} /dist/
      docker run --platform linux/${ARCH} ${EMULARCH} -v "$PWD/dist:/dist" ${asset_image} cp /assets/${asset_filename} /dist/
    #    #rm $PWD/test/*
    #    #cp $PWD/dist/${asset_filename} $PWD/dist/${asset_filename}
    else
      echo "Image already exists!!!"
      [ $ignore_errors -eq 0 ] && exit 1  
    fi
  fi


  test_arr=($test_platforms)
  for test_platform in "${test_arr[@]}"; do
    echo "Test: ${test_platform}"
    docker run --platform linux/${ARCH} -e platform -e test_platform=${test_platform} -e asset_filename=${asset_filename} ${EMULARCH} -v "$PWD/scripts/:/scripts" -v "$PWD/dist:/dist" ${test_platform} /scripts/test.sh
    retval=$?
    if [ $retval -ne 0 ]; then
      echo "!!! Error testing ${asset_filename} on ${test_platform}"
    fi
  done
done

#if [ -z "$DOCKER_USER" ]; then 
#  echo "No docker user defined exiting"
#  exit 0
#fi
#echo "preparing to tag and push docker hub asset for TAG: $TAG"
#if [ -z "$DOCKER_PASSWORD" ]; then 
#  echo "No docker password defined exiting"
#  exit 1
#fi

docker_asset=${REPO_SLUG}-${ruby_version}-${platform}:${asset_version}

echo "Docker Hub Asset: ${docker_asset}"

# echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USER" --password-stdin

docker tag ${asset_image} ${docker_asset}
docker push ${docker_asset}

#ver=${asset_version%+*}
#prefix=${ver%-*}
#prerel=${ver/#$prefix}
#if [ -z "$prerel" ]; then 
#  echo "tagging as latest asset"
#  latest_asset=${REPO_SLUG}-${ruby_version}-${platform}:latest
#  docker tag ${asset_image} ${latest_asset}
#  docker push ${latest_asset}
#fi

