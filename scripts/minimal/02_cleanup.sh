#!/bin/bash

NETWORK_NAME=minimal_flame_docker_backend_test

container_ids=$(docker ps -aq --filter "name=minimal")
if [ -n "$container_ids" ]; then
  docker rm -f $container_ids
fi

docker network rm -f "$NETWORK_NAME"
