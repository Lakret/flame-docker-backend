# FlameDockerBackend

Docker-out-of-Docker backend for [FLAME](https://github.com/phoenixframework/flame).

Provisions runner nodes as Docker containers via the Docker Engine API. The parent app runs inside a container and talks to the host Docker daemon through the mounted socket (`/var/run/docker.sock`).

## Installation

```elixir
def deps do
  [
    {:flame_docker_backend, "~> 0.1.0"}
  ]
end
```

## Configuration

```elixir
config :flame, FlameDockerBackend,
  image: "my-app:latest",
  network: "my_network"
```

Required:
- `:image` — Docker image to use for runner containers
- `:network` — User-defined Docker network (required for DNS resolution between containers)

Optional:
- `:boot_timeout` — How long to wait for runner to connect back (default: 30000ms)
- `:docker_socket_path` — Path to Docker socket (default: `/var/run/docker.sock`)
- `:env` — Additional environment variables for runner containers

## Testing

### `test_apps/minimal`

A minimal test application for integration testing.

**Build the Docker image:**

```bash
# from the flame_docker_backend project's root directory
docker build -t minimal:latest -f test_apps/minimal/Dockerfile .
```

**Create a Docker network:**

```bash
docker network create minimal_flame_docker_backend_test
```

**Run the parent container:**

```bash
docker run -it --rm \
  --name minimal-parent \
  --network minimal_flame_docker_backend_test \
  -v /mnt/wsl/shared-docker/docker.sock:/var/run/docker.sock \
  -e RELEASE_NODE=minimal@minimal-parent \
  -e RELEASE_COOKIE=test_cookie \
  -e FLAME_IMAGE=minimal:latest \
  -e FLAME_NETWORK=minimal_flame_docker_backend_test \
  minimal:latest bin/minimal start_iex
```

Mount correct Docker socket location:

- on Linux: `-v /var/run/docker.sock:/var/run/docker.sock`
- on WSL2: `-v /mnt/wsl/shared-docker/docker.sock:/var/run/docker.sock`

**Test the FLAME backend in IEx:**

```elixir
# Spawns a runner container and executes the function there
Minimal.test_flame_backend_lambda()

# Or test manually:
FLAME.call(Minimal.Runner, fn -> {node(), self()} end)
```

**Watch Docker activity** (in another terminal):

```bash
docker ps -a --filter "name=minimal"
```

**Cleanup:**

```bash
docker network rm flame_test
```