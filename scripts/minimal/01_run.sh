#!/bin/bash

CMD=$1
FLAGS=$2

if [ -z "$CMD" ]; then
  CMD="bin/minimal start_iex"

  if [ -z "$FLAGS" ]; then
    FLAGS="-it"
  fi
fi

DOCKER_SOCKET_PATH=/var/run/docker.sock
WSL_DOCKER_SOCKET_PATH=/mnt/wsl/shared-docker/docker.sock
MACOS_DOCKER_SOCKET_PATH=/Users/$(whoami)/.docker/run/docker.sock
if [ -f "$WSL_DOCKER_SOCKET_PATH" ]; then
  DOCKER_SOCKET_PATH=$WSL_DOCKER_SOCKET_PATH
elif [ -f "$MACOS_DOCKER_SOCKET_PATH" ]; then
  DOCKER_SOCKET_PATH=$MACOS_DOCKER_SOCKET_PATH
fi

NETWORK_NAME=minimal_flame_docker_backend_test
docker network rm -f "$NETWORK_NAME"
docker network create "$NETWORK_NAME"

docker build -t minimal:latest -f test_apps/minimal/Dockerfile .

# shellcheck disable=SC2086
docker run $FLAGS --rm \
  --name minimal-parent \
  --network "$NETWORK_NAME" \
  -v "$DOCKER_SOCKET_PATH:/var/run/docker.sock" \
  -e FLAME_IMAGE=minimal:latest \
  -e FLAME_NETWORK="$NETWORK_NAME" \
  minimal:latest $CMD
