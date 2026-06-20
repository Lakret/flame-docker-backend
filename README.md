# FLAMEDockerBackend

A [FLAME](https://github.com/phoenixframework/flame) backend that runs runners
as Docker containers on the host machine via the Docker Engine API (Docker-out-of-Docker) —
no cloud account, no Kubernetes, no external infrastructure required.

The parent app runs inside a container and provisions runners by talking to the host Docker daemon
through the mounted socket.
Runners are ordinary containers started from the same image, connected to the same user-defined network,
and shut down automatically when idle.

## Features

- **Zero-infrastructure local scaling / resource usage control** — provision FLAME runners on your local machine
or any host with Docker. No cloud provider setup or k8s needed. Allows limiting resources per specific task.
- **Docker-out-of-Docker** — the parent runs inside a container and talks to the host daemon through
a mounted socket (`/var/run/docker.sock`). No privileged containers or sidecars required.
- **Cross-platform socket detection** — automatically finds the Docker socket on Linux, macOS (Docker Desktop),
and WSL2, or accepts an explicit path.
- **Minimal dependencies** — depends only on FLAME and Jason libraries. Docker API calls via UNIX socket
are done with httpc, so no additional HTTP client libraries are used.
- **Image pull on demand** — if the configured image is not present locally,
the backend pulls it before booting the runner.
- **Environment propagation** — `ERL_AFLAGS` and `ERL_ZFLAGS` are forwarded from the parent to runners automatically,
additional environment variables are configurable.

## Installation

```elixir
def deps do
  [
    {:flame_docker_backend, "~> 0.1.0"}
  ]
end
```

## Configuration

Add to your `config/runtime.exs`:

```elixir
config :flame, :backend, FLAMEDockerBackend

config :flame, FLAMEDockerBackend,
  image: "my-app:latest",
  network: "my_network"
```

Then add a `FLAME.Pool` to your application supervisor:

```elixir
{FLAME.Pool,
 name: MyApp.Runner,
 backend: FLAMEDockerBackend,
 min: 0,
 max: 4,
 idle_shutdown_after: 30_000}
```

**Required options:**
- `:image` — Docker image to use for runner containers
- `:network` — User-defined Docker network (required for DNS resolution between parent and runners)

**Optional options:**
- `:boot_timeout` — Milliseconds to wait for a runner to connect back (default: `30_000`)
- `:docker_socket_path` — Path to the Docker socket (auto-detected if omitted)
- `:env` — Additional environment variables to set on runner containers (`PHX_SERVER` may be overridden; `FLAME_PARENT` may not)
- `:host_config` — Docker `HostConfig` map (resource limits, binds, etc.)
- `:mounts` — Docker `Mounts` list (bind mounts, volumes, tmpfs)
- `:cmd` — Docker `Cmd` override (list of strings)
- `:keep_runners` — When `true`, leave exited runner containers for log inspection (default: `false`, containers are removed)

See [Available configurations](#available-configurations) for examples.

## Parent deployment

The parent must run as a **distributed release** on a **user-defined Docker network** with:

1. **Docker socket mounted** — `-v /var/run/docker.sock:/var/run/docker.sock` (or your platform path)
2. **Stable container name** — `--name my-app-parent` so Docker DNS matches the Erlang node hostname
3. **Same network as runners** — `--network my_network` (must match `:network` config)
4. **Shared cookie** — set `RELEASE_COOKIE` on the parent; it is forwarded to runners automatically

Example:

```bash
docker run --rm \
  --name my-app-parent \
  --network my_network \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e RELEASE_COOKIE=my-secret-cookie \
  my-app:latest
```

**Docker socket paths by platform:**

| Platform | Socket path |
|----------|-------------|
| Linux | `/var/run/docker.sock` |
| WSL2 | `/mnt/wsl/shared-docker/docker.sock` |
| macOS (Docker Desktop) | `~/.docker/run/docker.sock` |

Mount it into the parent container with `-v <host-socket>:/var/run/docker.sock`.

## Integration Examples

**Basic Elixir Applications**

See integration steps in
[minimal test app's README](test_apps/minimal/README.md#flame--flamedockerbackend-integration-steps).

**Phoenix Projects**

See integration steps in
[phx_minimal test app's README](test_apps/phx_minimal/README.md#flame--flamedockerbackend-integration-steps).

## Available configurations

Runner container options use Docker Engine API field names. Set them globally in
`config :flame, FLAMEDockerBackend`, per pool via the `backend` tuple, or at
runtime when starting a pool or `FLAME.Runner`.

**Application config** (`config/runtime.exs`):

```elixir
config :flame, FLAMEDockerBackend,
  image: "my-app:latest",
  network: "my_network",
  host_config: %{
    "Memory" => 2_147_483_648,
    "NanoCpus" => 2_000_000_000,
    "Ulimits" => [%{"Name" => "nofile", "Soft" => 65_536, "Hard" => 65_536}]
  },
  mounts: [
    %{"Type" => "bind", "Source" => "/data/models", "Target" => "/models", "ReadOnly" => true}
  ]
```

**Per-pool overrides** (static or dynamic values at startup):

```elixir
{FLAME.Pool,
 name: MyApp.GpuRunner,
 backend:
   {FLAMEDockerBackend,
    image: "my-app:gpu",
    network: System.fetch_env!("DOCKER_NETWORK"),
    host_config: %{"Memory" => 4_294_967_296, "NanoCpus" => 4_000_000_000},
    mounts: [
      %{
        "Type" => "bind",
        "Source" => "/var/run/docker.sock",
        "Target" => "/var/run/docker.sock",
        "ReadOnly" => true
      }
    ]},
 min: 0,
 max: 2,
 idle_shutdown_after: 30_000}
```

**One-off runner** with custom container settings:

```elixir
{:ok, runner} =
  FLAME.Runner.start_link(
    backend:
      {FLAMEDockerBackend,
       image: "my-app:latest",
       network: "my_network",
       cmd: ["bin/my_app", "start"]}
  )
```

Pool-level `backend` options override application config. Wiring fields
(`Hostname`, `NetworkingConfig`, `FLAME_PARENT`, etc.) are always set by the
backend and cannot be overridden.

## Testing

**Unit tests** (default):

```bash
mix test
```

**Docker integration tests** — build the test app images, start parent containers, and
run `FLAME.call` via release RPC. Requires a running Docker daemon and the socket path
detected by `DockerAPI.default_socket_path/0`:

```bash
mix test.docker
```

### `test_apps/minimal`

A minimal test application for integration testing.

**Run everything** (from the project root):

```bash
./scripts/minimal/01_run.sh
```

The script builds the image, recreates the `minimal_flame_docker_backend_test` network,
picks the Docker socket for your platform (Linux, WSL2, or macOS), and starts the parent container with IEx.

Optional arguments:

```bash
# custom command (FLAGS default omitted when CMD is provided)
./scripts/minimal/01_run.sh "bin/minimal remote"

# custom docker run flags and command
./scripts/minimal/01_run.sh "bin/minimal start_iex" "-it"
```

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

# Execute many tasks — observe that only max containers from the FLAME.Pool child spec are spawned:
(for _ <- 1..10, do: Task.async(fn -> Minimal.test_flame_backend_lambda() end)) |> Task.await_many(120_000)
# Or even more tasks:
(for _ <- 1..10_000, do: Task.async(fn -> Minimal.test_flame_backend_lambda(:infinity) end)) |> Task.await_many(:infinity)
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

### `test_apps/phx_minimal`

A Phoenix test application with a LiveView UI for integration testing.

**Run everything** (from the project root):

```bash
./scripts/phx_minimal/01_run.sh
```

The script builds the image, recreates the `phx_minimal_flame_docker_backend_test` network,
picks the Docker socket for your platform (Linux, WSL2, or macOS),
and starts the parent container with IEx on port 4000.

Optional arguments:

```bash
# custom docker run flags
./scripts/phx_minimal/01_run.sh "-d"
```

**Try the FLAME backend in the browser:**

Open [http://localhost:4000](http://localhost:4000) and click **Spawn FLAME task**.
Each click runs `FLAME.call` on a remote runner via `start_async`;
completed colors are saved to the database and shown in the UI.
Click rapidly to queue multiple tasks — the pool runs up to `max` concurrent runners.

**Connect to the FLAME runner node:**

```bash
# find CONTAINER_ID of the node you want to connect to remotely:
docker ps

docker exec -it $CONTAINER_ID bin/phx_minimal remote
```

**Watch Docker activity** (in another terminal):

```bash
docker ps -a --filter "name=phx_minimal"
```

**Cleanup:**

```bash
./scripts/phx_minimal/02_cleanup.sh
```

Removes all containers matching `phx_minimal` (parent and FLAME runners) and the test network.
