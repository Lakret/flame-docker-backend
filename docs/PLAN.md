# Implementation Plan: FLAME Docker Backend (DooD)

A `FLAME.Backend` that provisions runner nodes as Docker containers via the Docker Engine API.
The parent app itself runs inside a container and talks to the host Docker daemon
through the mounted socket (`/var/run/docker.sock`, `unix:///mnt/wsl/shared-docker/docker.sock` on WSL2 ) —
Docker-out-of-Docker.

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Host Docker daemon                              │
│                                                  │
│  ┌────────────────────┐  ┌────────────────────┐  │
│  │ Parent container   │  │ Runner container   │  │
│  │                    │  │                    │  │
│  │  FlameDockerBackend│  │  FLAME.Terminator  │  │
│  │  (FLAME.Pool)      │  │  (your app)        │  │
│  │        │           │  │        │           │  │
│  │        │  Docker API (unix socket)         │  │
│  │        └───────────┼──┘        │           │  │
│  │                    │           │           │  │
│  └────────────────────┘  └────────────────────┘  │
│         /var/run/docker.sock                     │
└──────────────────────────────────────────────────┘
```

## 1. Docker API Client (`FlameDockerBackend.DockerAPI`)

Thin wrapper over the Docker Engine API via Unix socket using OTP's built-in `:httpc`.

`:httpc` supports Unix sockets natively via `unix_socket` and `ipfamily: :local` options:

```elixir
:httpc.set_options([{:unix_socket, ~c"/var/run/docker.sock"}, {:ipfamily, :local}])
:httpc.request(~c"http://localhost/version")
```

No additional HTTP dependencies needed.

Default socket paths by platform:
- **Linux:** `/var/run/docker.sock`
- **macOS:** `/var/run/docker.sock` (Docker Desktop)
- **WSL2:** `/mnt/wsl/shared-docker/docker.sock` (when sharing Docker Desktop socket)

Endpoints needed:

- `POST /containers/create` — create a runner container
- `POST /containers/{id}/start` — start it
- `POST /containers/{id}/stop` — stop it
- `DELETE /containers/{id}` — remove it
- `GET /containers/{id}/json` — inspect (get IP, status)
- `POST /containers/{id}/wait` — (optional) wait for exit

All requests go to the Unix socket at a configurable path (default `/var/run/docker.sock`).

**Note:** `:httpc` options like `unix_socket` are per-profile. We should use a dedicated
`:httpc` profile (e.g., `:flame_docker`) to avoid interfering with other `:httpc` users
in the same BEAM.

## 2. Networking & Node Discovery

FLAME requires distributed Erlang between parent and runner. The runner reads
`FLAME_PARENT` and calls `Node.connect/1` back to the parent.

**Decision:** Always require a user-defined Docker network. The default `bridge`
network does not provide stable DNS between containers and is not supported.

Containers on a user-defined network reach each other by **container name** via
Docker's embedded DNS. We use those names as Erlang node hostnames — no IP
inspection, entrypoint wrappers, or post-start env injection.

### Network configuration

`:network` is **required** unless `kamal: true` is set (which defaults it to
`"kamal"`). `init/1` fails validation if neither is provided.

For apps deployed with **Kamal 2**, set `kamal: true` (or `network: "kamal"` directly).
Kamal 2 creates and attaches all app containers to a user-defined network named
`kamal`, which provides the same container-name DNS we rely on. See
[Kamal network changes](https://kamal-deploy.org/docs/upgrading/network-changes/).

When `kamal: true`:
- Default `:network` to `"kamal"` (explicit `:network` still wins).
- Document Kamal-specific setup: the parent web container should expose a
  **stable network alias** via `options.network-alias` in `deploy.yml` so
  `FLAME_PARENT` and the parent's own `--name` stay consistent across deploys
  (Kamal's default web container name includes a git commit hash and changes
  every deploy).

### Node naming

Both parent and runner use container names as Erlang node hostnames:

```
--name <node_base>@<container_name>
```

- **Parent:** resolve its container name on the configured network once in
  `init/1` (Docker API inspect of self, or `:parent_hostname` override).
  For Kamal, prefer a stable `network-alias` and set `:parent_hostname` to
  match it.
- **Runner:** assign an explicit container name at create time
  (`flame-<random_id>`). Set `Hostname` to the same value so the BEAM's
  default hostname matches what Docker DNS resolves.
- **FLAME_PARENT:** encode the parent's node as
  `<parent_node_base>@<parent_container_name>`. The runner connects back over
  the shared network using that name.
- **`host_env`:** `nil` — the runner's hostname is known at container create
  time; no runtime IP discovery env var is needed.

### Flow

1. `init/1` — resolve parent container name on `:network`; encode `FLAME_PARENT`.
2. `remote_boot/1` — create runner with explicit `name`, `Hostname`, and
   `NetworkingConfig.EndpointsConfig[network]`; start container.
3. Set `ERL_FLAGS=--name <runner_node_base>@<container_name>` on the runner.
4. Runner boots, reads `FLAME_PARENT`, calls `Node.connect/1` to parent by name.

## 3. `FlameDockerBackend` Module — Callbacks

### `init/1`

1. Merge `Application.get_env(:flame, FlameDockerBackend)` with pool opts.
2. Validate required config: `:image`, and either `:network` or `kamal: true`.
3. Optional config: `:docker_socket`, `:kamal`, `:parent_hostname`, `:cpu_shares`,
   `:memory`, `:nano_cpus`, `:ulimits`, `:mounts`, `:storage_opt`, `:boot_timeout`,
   `:env`, `:cmd`, `:log`.
4. If `kamal: true` and `:network` is unset, default `:network` to `"kamal"`.
5. Generate unique runner name: `"flame-#{rand_id(20)}"` (used as container name
   and Erlang hostname).
6. Resolve parent container name on the Docker network (inspect self, or
   `:parent_hostname` override).
7. `make_ref()` → encode `FLAME.Parent` with `host_env: nil`.
8. Build the env map with `FLAME_PARENT`, `PHX_SERVER=false`, user-provided env.
   Forward `RELEASE_COOKIE`, `ERL_AFLAGS`, and `ERL_ZFLAGS` from the parent
   when present.
9. Return `{:ok, state}`.

### `remote_boot/1`

1. Call Docker API: create container with the configured image, env, network,
   and optional `HostConfig` / `Mounts` (see §5).
   - Container `name` and `Hostname` = runner node base name.
   - Attach to the required user-defined network (`:network`, or `"kamal"` when
     `kamal: true`).
   - Set `ERL_FLAGS=--name <node_base>@<container_name>`.
   - Forward `RELEASE_COOKIE` from the parent so runner and parent share a cookie.
   - Set `HostConfig.AutoRemove: true` on create (safety net).
2. Start the container.
3. `receive` the `{parent_ref, {:remote_up, terminator_pid}}` message within `boot_timeout`.
4. Return `{:ok, terminator_pid, new_state}`.

On error / timeout: stop the container, `DELETE /containers/{id}`, return `{:error, reason}`.

### `remote_spawn_monitor/2`

Same as `FlyBackend` — delegate to `Node.spawn_monitor/2` and `Node.spawn_monitor/4`.
This is straightforward once distributed Erlang is connected.

### `system_shutdown/0`

Call `System.stop()`. The container will exit when the BEAM stops.

### Container cleanup

**Decision:** Use both `AutoRemove: true` at create time **and** explicit
`DELETE /containers/{id}` from the parent on every teardown path.

- **`AutoRemove`:** safety net — Docker removes the container after it exits,
  even if the parent crashes or misses a cleanup call.
- **Explicit `DELETE`:** primary cleanup — the parent stops (if still running)
  and deletes the container when the runner shuts down, boot fails, or the pool
  reclaims the runner. Keeps state predictable and frees the container name
  immediately.

Shared helper (e.g. `remove_container/2`): `POST .../stop` (ignore already-stopped),
then `DELETE .../containers/{id}` (ignore already-removed). Idempotent so double
cleanup with `AutoRemove` is fine.

Call sites:
- `remote_boot/1` error / timeout path
- Runner shutdown (after `system_shutdown/0` or unexpected disconnect)
- `handle_info/2` if we monitor container exit (optional v1)

### `handle_info/2` (optional)

Monitor the runner container via Docker API or process monitors.
Could handle unexpected container death. Likely not needed for v1.

## 4. Configuration

```elixir
# Generic Docker deployment
config :flame, FlameDockerBackend,
  image: "my-app:latest",
  docker_socket: "/var/run/docker.sock",  # default
  network: "my_network",                  # required — user-defined network
  parent_hostname: "my-app",              # optional — stable parent DNS name
  boot_timeout: 30_000,
  cpu_shares: 1024,                        # HostConfig.CpuShares
  memory: 2_147_483_648,                   # HostConfig.Memory (bytes)
  nano_cpus: 2_000_000_000,                # HostConfig.NanoCpus (2 CPUs)
  ulimits: [%{"Name" => "nofile", "Soft" => 65536, "Hard" => 65536}],
  mounts: [                                # top-level Mounts
    %{"Type" => "bind", "Source" => "/data/models", "Target" => "/models", "ReadOnly" => true}
  ],
  storage_opt: %{"size" => "10G"},         # HostConfig.StorageOpt
  env: %{
    "DATABASE_URL" => "...",
  }

# Kamal 2 deployment (network defaults to "kamal")
config :flame, FlameDockerBackend,
  image: "my-app:latest",
  kamal: true,
  parent_hostname: "my-app",               # match deploy.yml network-alias
  boot_timeout: 30_000
```

Per-pool overrides via the `backend` option in `FLAME.Pool`:

```elixir
{FLAME.Pool,
  name: MyRunner,
  backend: {FlameDockerBackend,
    image: "my-app:latest",
    nano_cpus: 2_000_000_000,
    memory: 2_147_483_648}}
```

## 5. Resource Limits & Mounts

**Decision:** Expose these Docker container-create fields as optional backend config.
Values pass through to the create payload (maps/lists as Docker expects).

| Config key     | Docker field              | Location        |
|----------------|---------------------------|-----------------|
| `:cpu_shares`  | `CpuShares`               | `HostConfig`    |
| `:memory`      | `Memory`                  | `HostConfig`    |
| `:nano_cpus`   | `NanoCpus`                | `HostConfig`    |
| `:ulimits`     | `Ulimits`                 | `HostConfig`    |
| `:storage_opt` | `StorageOpt`              | `HostConfig`    |
| `:mounts`      | `Mounts`                  | top-level       |

All optional — omit any key to leave that constraint unset. Accept per-pool
overrides via the `backend` option in `FLAME.Pool`.

**Notes:**
- `:memory` is bytes (integer). We may accept human-readable strings (`"2g"`)
  and normalize to bytes in `init/1`.
- `:nano_cpus` is 1 CPU = `1_000_000_000` (Docker's NanoCPUs unit).
- `:cpu_shares` is relative weight (default 1024); prefer `:nano_cpus` for
  hard CPU caps.
- `:ulimits` and `:mounts` are lists of maps matching the Docker API schema.
- `:storage_opt` requires a storage driver that supports it (e.g. `overlay2`
  with quota).

## 6. ERL_FLAGS / Node Naming

The parent must run as a distributed node (long names). The runner must also start with
`--name <runner_node_base>@<container_name>`. This is typically done via `ERL_FLAGS` or `RELEASE_NODE`.

**Plan:** Set `ERL_FLAGS=--name <node_base>@<container_name>` in the runner
container's environment. Container name is assigned at create time and doubles
as the Docker DNS hostname on the user-defined network.

Also forward `ERL_AFLAGS` and `ERL_ZFLAGS` from the parent if present (same as `FlyBackend`).

### Erlang cookie

**Decision:** Forward the parent's `RELEASE_COOKIE` env var to each runner
container. Elixir releases read this at boot to set the node cookie, so parent
and runner stay in sync without mounting cookie files.

In `init/1`, read `System.get_env("RELEASE_COOKIE")` from the parent and include
it in the runner env map. If the parent is not a release (no `RELEASE_COOKIE`),
the user must ensure both nodes share a cookie by other means (e.g. set
`RELEASE_COOKIE` on the parent container too).

## 7. Design Choices

1. **Unix socket HTTP client:** — use OTP `:httpc` with `unix_socket` + `ipfamily: :local`.
   Use a dedicated `:httpc` profile to isolate from other users.
2. **Docker network model:** — always require a user-defined
   network (`:network` is mandatory). Special Kamal 2 support via `kamal: true`
   (defaults network to `"kamal"`). Container names on that network are the
   Erlang node hostnames; default `bridge` is not supported.
3. **Runner hostname discovery:** — use container name as
   hostname (Docker DNS on user-defined networks). Set `name` + `Hostname` at
   create time; set `ERL_FLAGS` accordingly. No entrypoint wrapper or post-start
   IP inspect.
4. **Container cleanup:** — set `HostConfig.AutoRemove: true`
   on create as a safety net, and always call explicit `DELETE` from the parent
   on teardown (boot failure, runner shutdown, pool reclaim). Use an idempotent
   stop-then-delete helper.
5. **Erlang cookie:** — forward the parent's `RELEASE_COOKIE`
   env var to runner containers. No cookie file mounting.
6. **Resource limits:** — expose optional `:cpu_shares`,
   `:memory`, `:nano_cpus`, `:ulimits`, `:mounts`, and `:storage_opt`, mapped
   to Docker `HostConfig` / `Mounts` on container create.
7. **Volumes:** — covered by `:mounts` (bind mounts, volumes,
   tmpfs per Docker `Mounts` schema).

## 8. Implementation Order

1. Docker API client (create, start, stop, remove, inspect).
2. `init/1` — config merging, parent encoding.
3. `remote_boot/1` — container creation, start, wait for connect-back.
4. `remote_spawn_monitor/2` — trivial, same as FlyBackend.
5. `system_shutdown/0` — `System.stop()`.
6. Integration test with a real Docker daemon.
7. Documentation and hex package metadata.
