# Docker API Client Implementation Plan

Detailed implementation guide for `FLAMEDockerBackend.DockerAPI` — a thin wrapper over Docker Engine API via Unix socket using OTP's `:httpc`.

## Overview

Create `lib/flame_docker_backend/docker_api.ex` that provides functions to:
- Create containers
- Start containers
- Stop containers
- Remove containers
- Inspect containers

All communication uses Unix socket HTTP via `:httpc` with a dedicated profile.

`DockerAPI` is a thin transport layer: it sends the Docker API JSON body as-is.
The backend module (`FLAMEDockerBackend`) builds the create payload by merging
user `:host_config` / `:mounts` with required wiring fields — see **Container
Create Payload** below and `docs/PLAN.md` §5.

---

## Container Create Payload (backend caller)

`DockerAPI.create_container/2` accepts the final merged Docker API body. The
backend implements `build_create_body/1` before calling it.

### User passthrough

| Backend config | Docker field     | Behavior                          |
|----------------|------------------|-----------------------------------|
| `:host_config` | `"HostConfig"`   | Any valid map — no whitelisted keys |
| `:mounts`      | `"Mounts"`       | Top-level list — passthrough      |

Resource limits and other host options go directly in `:host_config`:

```elixir
host_config: %{
  "Memory" => 2_147_483_648,
  "NanoCpus" => 2_000_000_000,
  "Ulimits" => [%{"Name" => "nofile", "Soft" => 65536, "Hard" => 65536}]
}
```

### Backend overrides / extensions

These fields are always set or merged by the backend; wiring keys win on conflict:

| Field | Backend action |
|-------|----------------|
| Container `name` (query param) | Set to `"flame-<random_id>"` |
| `"Image"` | From `:image` |
| `"Hostname"` | Same as container name (Docker DNS / Erlang hostname) |
| `"NetworkingConfig"."EndpointsConfig"."<network>"` | Attach to required user-defined network |
| `"Env"` | Merge user `:env` with `FLAME_PARENT`, `ERL_FLAGS`, `PHX_SERVER`, forwarded cookie/flags; wiring wins |
| `"HostConfig"."AutoRemove"` | Always `true` (merged over user `:host_config`) |
| `"Cmd"` | From `:cmd` when set |

**Docker socket:** `docker_socket` configures the **parent's** `:httpc` profile
only. Runners do not get a socket mount unless the user adds one via `:mounts` or
`"Binds"` in `:host_config`.

**Parent node discovery:** encoded in `FLAME_PARENT` env and `"Hostname"` /
container `name` — no extra `HostConfig` fields required.

Example merge for `"HostConfig"`:

```elixir
Map.merge(user_host_config, %{"AutoRemove" => true})
```

---

## Step 1: Create the Module Skeleton

Create file `lib/flame_docker_backend/docker_api.ex`:

```elixir
defmodule FLAMEDockerBackend.DockerAPI do
  @moduledoc """
  Thin wrapper over Docker Engine API via Unix socket.

  Uses OTP `:httpc` with a dedicated profile (`:flame_docker`) to avoid
  interfering with other `:httpc` users in the same BEAM.
  """

  @default_socket "/var/run/docker.sock"
  @profile :flame_docker
  @docker_api_version "v1.43"

  @type container_id :: String.t()
  @type error :: {:error, term()}
end
```

---

## Step 2: Implement Profile Management

Add functions to start and configure the `:httpc` profile.

### 2.1 Add `start_profile/1`

```elixir
@doc """
Starts the dedicated :httpc profile for Docker API communication.

Call this once during application startup or in `init/1` of the backend.
Returns `:ok` if already started.
"""
@spec start_profile(String.t()) :: :ok | {:error, term()}
def start_profile(socket_path \\ @default_socket) do
  case :inets.start(:httpc, profile: @profile) do
    {:ok, _pid} ->
      configure_profile(socket_path)

    {:error, {:already_started, _pid}} ->
      configure_profile(socket_path)

    {:error, reason} ->
      {:error, reason}
  end
end

defp configure_profile(socket_path) do
  :httpc.set_options(
    [
      {:unix_socket, String.to_charlist(socket_path)},
      {:ipfamily, :local}
    ],
    @profile
  )
end
```

### 2.2 Add `stop_profile/0`

```elixir
@doc """
Stops the dedicated :httpc profile.
"""
@spec stop_profile() :: :ok
def stop_profile do
  :inets.stop(:httpc, @profile)
  :ok
rescue
  _ -> :ok
end
```

---

## Step 3: Implement HTTP Request Helpers

Add private helper functions for making HTTP requests.

### 3.1 Add `request/3` helper

```elixir
defp request(method, path, body \\ nil) do
  url = ~c"http://localhost/#{@docker_api_version}#{path}"

  request =
    case body do
      nil ->
        {url, []}

      body when is_map(body) ->
        json_body = Jason.encode!(body)
        {url, [{'Content-Type', 'application/json'}], 'application/json', json_body}
    end

  case :httpc.request(method, request, [], [], @profile) do
    {:ok, {{_http_version, status_code, _reason}, _headers, response_body}} ->
      handle_response(status_code, response_body)

    {:error, reason} ->
      {:error, {:httpc_error, reason}}
  end
end

defp handle_response(status_code, body) when status_code in 200..299 do
  case body do
    [] -> {:ok, nil}
    body -> {:ok, Jason.decode!(to_string(body))}
  end
end

defp handle_response(status_code, body) do
  error_body =
    case body do
      [] -> nil
      body -> Jason.decode!(to_string(body))
    end

  {:error, {:docker_error, status_code, error_body}}
end
```

---

## Step 4: Implement Container Operations

### 4.1 Add `create_container/2`

```elixir
@doc """
Creates a new container.

## Parameters

- `name` - Container name (string)
- `config` - Full Docker API create body map. Keys commonly include:
  - `"Image"` (required) - Image name
  - `"Env"` - List of `"KEY=value"` strings
  - `"Hostname"` - Container hostname
  - `"HostConfig"` - Any valid `HostConfig` map (resource limits, binds, etc.)
  - `"NetworkingConfig"` - Network attachment configuration
  - `"Mounts"` - Top-level mount list
  - `"Cmd"` - Command to run (list of strings)

The backend builds this map via `build_create_body/1` before calling here.
`DockerAPI` does not merge or validate `HostConfig` fields.

## Returns

- `{:ok, %{"Id" => container_id, ...}}`
- `{:error, reason}`
"""
@spec create_container(String.t(), map()) :: {:ok, map()} | error()
def create_container(name, config) when is_binary(name) and is_map(config) do
  path = "/containers/create?name=#{URI.encode(name)}"
  request(:post, path, config)
end
```

### 4.2 Add `start_container/1`

```elixir
@doc """
Starts a created container.

## Parameters

- `container_id` - Container ID or name

## Returns

- `:ok` on success (204 response)
- `{:error, reason}` on failure
"""
@spec start_container(container_id()) :: :ok | error()
def start_container(container_id) when is_binary(container_id) do
  path = "/containers/#{URI.encode(container_id)}/start"

  case request(:post, path) do
    {:ok, _} -> :ok
    {:error, {:docker_error, 304, _}} -> :ok
    error -> error
  end
end
```

### 4.3 Add `stop_container/2`

```elixir
@doc """
Stops a running container.

## Parameters

- `container_id` - Container ID or name
- `timeout` - Seconds to wait before killing (default: 10)

## Returns

- `:ok` on success
- `{:error, reason}` on failure
"""
@spec stop_container(container_id(), non_neg_integer()) :: :ok | error()
def stop_container(container_id, timeout \\ 10) when is_binary(container_id) do
  path = "/containers/#{URI.encode(container_id)}/stop?t=#{timeout}"

  case request(:post, path) do
    {:ok, _} -> :ok
    {:error, {:docker_error, 304, _}} -> :ok
    {:error, {:docker_error, 404, _}} -> :ok
    error -> error
  end
end
```

### 4.4 Add `remove_container/2`

```elixir
@doc """
Removes a container.

## Parameters

- `container_id` - Container ID or name
- `opts` - Options keyword list:
  - `:force` - Force remove running container (default: false)
  - `:v` - Remove associated volumes (default: false)

## Returns

- `:ok` on success
- `{:error, reason}` on failure
"""
@spec remove_container(container_id(), keyword()) :: :ok | error()
def remove_container(container_id, opts \\ []) when is_binary(container_id) do
  force = if Keyword.get(opts, :force, false), do: "true", else: "false"
  v = if Keyword.get(opts, :v, false), do: "true", else: "false"
  path = "/containers/#{URI.encode(container_id)}?force=#{force}&v=#{v}"

  case request(:delete, path) do
    {:ok, _} -> :ok
    {:error, {:docker_error, 404, _}} -> :ok
    error -> error
  end
end
```

### 4.5 Add `inspect_container/1`

```elixir
@doc """
Returns low-level information about a container.

## Parameters

- `container_id` - Container ID or name

## Returns

- `{:ok, container_info}` - Map with container details
- `{:error, reason}` on failure
"""
@spec inspect_container(container_id()) :: {:ok, map()} | error()
def inspect_container(container_id) when is_binary(container_id) do
  path = "/containers/#{URI.encode(container_id)}/json"
  request(:get, path)
end
```

---

## Step 5: Add Convenience Functions

### 5.1 Add `stop_and_remove_container/2`

This is the idempotent cleanup helper mentioned in PLAN.md.

```elixir
@doc """
Stops and removes a container. Idempotent — ignores already-stopped
or already-removed containers.

## Parameters

- `container_id` - Container ID or name
- `stop_timeout` - Seconds to wait before killing (default: 5)

## Returns

- `:ok` on success
- `{:error, reason}` on failure
"""
@spec stop_and_remove_container(container_id(), non_neg_integer()) :: :ok | error()
def stop_and_remove_container(container_id, stop_timeout \\ 5) do
  with :ok <- stop_container(container_id, stop_timeout),
       :ok <- remove_container(container_id, force: true) do
    :ok
  end
end
```

### 5.2 Add `version/0` for health checks

```elixir
@doc """
Returns Docker daemon version info. Useful for health checks.

## Returns

- `{:ok, version_info}` - Map with version details
- `{:error, reason}` on failure
"""
@spec version() :: {:ok, map()} | error()
def version do
  request(:get, "/version")
end
```

---

## Step 6: Add Jason Dependency

Update `mix.exs` to add Jason for JSON encoding/decoding:

```elixir
defp deps do
  [
    {:flame, "~> 0.5"},
    {:jason, "~> 1.4"}
  ]
end
```

Also add `:inets` to `extra_applications`:

```elixir
def application do
  [
    extra_applications: [:logger, :inets]
  ]
end
```

---

## Step 7: Write Tests

Create `test/flame_docker_backend/docker_api_test.exs`:

```elixir
defmodule FLAMEDockerBackend.DockerAPITest do
  use ExUnit.Case, async: false

  alias FLAMEDockerBackend.DockerAPI

  @moduletag :docker

  setup_all do
    socket = System.get_env("DOCKER_SOCKET", "/var/run/docker.sock")

    case DockerAPI.start_profile(socket) do
      :ok -> :ok
      {:error, reason} -> raise "Cannot start Docker profile: #{inspect(reason)}"
    end

    on_exit(fn -> DockerAPI.stop_profile() end)
    :ok
  end

  describe "version/0" do
    test "returns Docker version info" do
      assert {:ok, info} = DockerAPI.version()
      assert is_binary(info["Version"])
      assert is_binary(info["ApiVersion"])
    end
  end

  describe "container lifecycle" do
    @tag timeout: 60_000
    test "create, start, inspect, stop, remove" do
      name = "flame-test-#{:rand.uniform(1_000_000)}"

      config = %{
        "Image" => "alpine:latest",
        "Cmd" => ["sleep", "30"],
        "HostConfig" => %{
          "AutoRemove" => false,
          "Memory" => 64 * 1024 * 1024,
          "Ulimits" => [%{"Name" => "nofile", "Soft" => 1024, "Hard" => 2048}]
        }
      }

      # Create
      assert {:ok, %{"Id" => container_id}} = DockerAPI.create_container(name, config)
      assert is_binary(container_id)

      # Start
      assert :ok = DockerAPI.start_container(container_id)

      # Inspect
      assert {:ok, info} = DockerAPI.inspect_container(container_id)
      assert info["State"]["Running"] == true
      assert info["Name"] == "/#{name}"

      # Stop
      assert :ok = DockerAPI.stop_container(container_id, 1)

      # Verify stopped
      assert {:ok, info} = DockerAPI.inspect_container(container_id)
      assert info["State"]["Running"] == false

      # Remove
      assert :ok = DockerAPI.remove_container(container_id)

      # Verify removed
      assert {:error, {:docker_error, 404, _}} = DockerAPI.inspect_container(container_id)
    end
  end

  describe "stop_and_remove_container/2" do
    test "is idempotent" do
      name = "flame-test-#{:rand.uniform(1_000_000)}"

      config = %{
        "Image" => "alpine:latest",
        "Cmd" => ["sleep", "30"]
      }

      {:ok, %{"Id" => container_id}} = DockerAPI.create_container(name, config)
      :ok = DockerAPI.start_container(container_id)

      # First removal
      assert :ok = DockerAPI.stop_and_remove_container(container_id)

      # Second removal (should not error)
      assert :ok = DockerAPI.stop_and_remove_container(container_id)
    end
  end
end
```

---

## Step 8: Final Module Structure

The complete file at `lib/flame_docker_backend/docker_api.ex` should have:

```elixir
defmodule FLAMEDockerBackend.DockerAPI do
  @moduledoc """
  Thin wrapper over Docker Engine API via Unix socket.

  Uses OTP `:httpc` with a dedicated profile (`:flame_docker`) to avoid
  interfering with other `:httpc` users in the same BEAM.
  """

  @default_socket "/var/run/docker.sock"
  @profile :flame_docker
  @docker_api_version "v1.43"

  @type container_id :: String.t()
  @type error :: {:error, term()}

  # Profile management
  @spec start_profile(String.t()) :: :ok | {:error, term()}
  def start_profile(socket_path \\ @default_socket)

  @spec stop_profile() :: :ok
  def stop_profile()

  # Container operations
  @spec create_container(String.t(), map()) :: {:ok, map()} | error()
  def create_container(name, config)

  @spec start_container(container_id()) :: :ok | error()
  def start_container(container_id)

  @spec stop_container(container_id(), non_neg_integer()) :: :ok | error()
  def stop_container(container_id, timeout \\ 10)

  @spec remove_container(container_id(), keyword()) :: :ok | error()
  def remove_container(container_id, opts \\ [])

  @spec inspect_container(container_id()) :: {:ok, map()} | error()
  def inspect_container(container_id)

  # Convenience
  @spec stop_and_remove_container(container_id(), non_neg_integer()) :: :ok | error()
  def stop_and_remove_container(container_id, stop_timeout \\ 5)

  @spec version() :: {:ok, map()} | error()
  def version()

  # Private helpers
  defp request(method, path, body \\ nil)
  defp handle_response(status_code, body)
  defp configure_profile(socket_path)
end
```

---

## Verification Checklist

After implementation:

1. [ ] `mix compile` succeeds with no warnings
2. [ ] `mix test --exclude docker` passes (existing tests)
3. [ ] `mix test --only docker` passes (requires Docker daemon access)
4. [ ] `DockerAPI.version/0` returns valid version info
5. [ ] Container lifecycle test creates, starts, inspects, stops, and removes a container
6. [ ] `stop_and_remove_container/2` is idempotent

---

## Notes for Implementation

1. **Charlist vs String**: `:httpc` uses charlists. Convert strings with `String.to_charlist/1` or use `~c` sigil.

2. **Error handling**: The `handle_response/2` function treats 2xx as success. 304 (Not Modified) from stop means already stopped. 404 from remove means already removed.

3. **Profile isolation**: Using a dedicated profile (`:flame_docker`) ensures our Unix socket config doesn't affect other `:httpc` users.

4. **Docker API version**: Using `v1.43` which is widely supported. Adjust if needed.

5. **WSL2 socket**: The socket path is configurable. WSL2 users pass `/mnt/wsl/shared-docker/docker.sock`.

6. **No external deps**: Only adds Jason (already common in Elixir projects). All HTTP via OTP's `:httpc`.

7. **HostConfig passthrough**: `create_container/2` accepts any `"HostConfig"` map.
   Backend wiring (`AutoRemove`, network, env, hostname) is applied in
   `FLAMEDockerBackend.build_create_body/1`, not in `DockerAPI`.
