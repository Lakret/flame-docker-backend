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

**Run everything** (from the project root):

```bash
./scripts/minimal/01_run.sh
```

The script builds the image, recreates the `minimal_flame_docker_backend_test` network, picks the Docker socket for your platform (Linux, WSL2, or macOS), and starts the parent container with IEx.

Optional arguments:

```bash
# custom command (FLAGS default omitted when CMD is provided)
./scripts/minimal/01_run.sh "bin/minimal remote"

# custom docker run flags and command
./scripts/minimal/01_run.sh "bin/minimal start_iex" "-it"
```

**Manual setup** (if you prefer not to use the script):

```bash
docker build -t minimal:latest -f test_apps/minimal/Dockerfile .
docker network create minimal_flame_docker_backend_test

docker run -it --rm \
  --name minimal-parent \
  --network minimal_flame_docker_backend_test \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e FLAME_IMAGE=minimal:latest \
  -e FLAME_NETWORK=minimal_flame_docker_backend_test \
  minimal:latest bin/minimal start_iex
```

Mount the correct Docker socket for your platform:

- on Linux: `-v /var/run/docker.sock:/var/run/docker.sock`
- on WSL2: `-v /mnt/wsl/shared-docker/docker.sock:/var/run/docker.sock`
- on macOS: `-v ~/.docker/run/docker.sock:/var/run/docker.sock`

Optionally, configure a nicer name for the parent node with `-e RELEASE_NODE=minimal@minimal-parent`.

**Test the FLAME backend in IEx:**

```elixir
# Spawns a runner container and executes the function there
Minimal.test_flame_backend_lambda()

# Or test manually:
FLAME.call(Minimal.Runner, fn ->
  IO.puts("hey from remote")
  System.get_env() |> dbg
  {node(), self()}
end)

# Execute many tasks, you can observe that we only spawning max number of containers specified in the FLAME.Pool
# child spec:
(for _ <- 1..10, do: Task.async(fn -> Minimal.test_flame_backend_lambda() end)) |> Task.await_many(120_000)
```

**Connect to the FLAME runner node:**

```bash
# find CONTAINER_ID of the node you want to connect to remotely:
docker ps

docker exec -it $CONTAINER_ID bin/minimal remote
```

**Watch Docker activity** (in another terminal):

```bash
docker ps -a --filter "name=minimal"
```

**Cleanup:**

```bash
./scripts/minimal/02_cleanup.sh
```

Removes all containers matching `minimal` (parent and FLAME runners) and the test network.
