#!/bin/bash

FLAGS=$1

if [ -z "$FLAGS" ]; then
  FLAGS="-it"
fi

WSL_DOCKER_SOCKET_PATH=/mnt/wsl/shared-docker/docker.sock
MACOS_DOCKER_SOCKET_PATH=/Users/$(whoami)/.docker/run/docker.sock
if [ -S "$WSL_DOCKER_SOCKET_PATH" ]; then
  DOCKER_SOCKET_PATH=$WSL_DOCKER_SOCKET_PATH
elif [ -S "$MACOS_DOCKER_SOCKET_PATH" ]; then
  DOCKER_SOCKET_PATH=$MACOS_DOCKER_SOCKET_PATH
else
  DOCKER_SOCKET_PATH=/var/run/docker.sock
fi
echo "Using Docker socket at: $DOCKER_SOCKET_PATH."

NETWORK_NAME=phx_minimal_flame_docker_backend_test
docker network rm -f "$NETWORK_NAME"
docker network create "$NETWORK_NAME"

docker build -t phx_minimal:latest -f test_apps/phx_minimal/Dockerfile .

# shellcheck disable=SC2086
docker run $FLAGS --rm \
  --name phx_minimal-parent \
  --network "$NETWORK_NAME" \
  -p 4000:4000 \
  -v "$DOCKER_SOCKET_PATH:/var/run/docker.sock" \
  -e SECRET_KEY_BASE=yU6FuZbC4EGZtSSR39kyGBPzG5S3XubPjhj+Har5+wsnogPrt+zg4zED8p02qINt \
  phx_minimal:latest bin/phx_minimal start_iex
