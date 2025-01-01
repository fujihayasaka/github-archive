#!/bin/bash
set -e

# Support the GH_GH_PAT secret if running in a Codespace
if [ -n "$GH_GH_PAT" ]; then
    echo "$GH_GH_PAT" | docker login --username token --password-stdin ghcr.io

    # Override GITHUB_TOKEN to use GH_GH_PAT which tends to have more access
    export GITHUB_TOKEN=$GH_GH_PAT
fi

# Don't 'set -x' before this point since the above code emits docker credentials.
set -x

BASE_IMAGE="ghcr.io/github/codespaces-base/codespaces-base:latest"
DOCKER_ID=codespace-nightly
TARGET_IMAGE="ghcr.io/github/authnd/${DOCKER_ID}:latest"

docker pull $BASE_IMAGE

docker rm -f $DOCKER_ID 2> /dev/null || true

echo "https://git:$GITHUB_TOKEN@github.com" > git-credentials
trap "rm -f git-credentials" EXIT

docker run --name $DOCKER_ID \
    --privileged --detach \
    --tmpfs /run/ \
    -v "${PWD}":/workspaces/authnd \
    -v "${PWD}/git-credentials":/root/.git-credentials \
    $BASE_IMAGE

SETUP_SCRIPT="$(cat "$(dirname "$0")"/setup-devcontainer.sh)"
docker exec --workdir /workspaces/authnd $DOCKER_ID bash -c "GITHUB_TOKEN=$GITHUB_TOKEN $SETUP_SCRIPT"

# Kill running container, commit result as the target, delete the temp container
docker kill $DOCKER_ID
docker commit $DOCKER_ID $TARGET_IMAGE
docker rm -f $DOCKER_ID

# Codespace creation will fail if workdir exists, so run the image we just
# created, cleanup mount points, and commit the result as the target again.
docker run --name $DOCKER_ID --privileged --detach --tmpfs /run/ $TARGET_IMAGE
docker exec $DOCKER_ID sudo rm -r /workspaces/authnd /root/.git-credentials
docker kill $DOCKER_ID
docker commit $DOCKER_ID $TARGET_IMAGE
docker rm -f $DOCKER_ID
