defmodule FlameDockerBackend.DockerAPI do
  @moduledoc """
  Thin wrapper over Docker Engine API via Unix socket.

  Transport only — sends JSON bodies as-is. `FlameDockerBackend` builds create
  payloads via `build_create_body/1` (see `docs/PLAN.md` §5).

  ## Dependencies

  - `:inets` — started in `extra_applications`; provides `:httpc`
  - `:jason` — JSON encode/decode for request/response bodies

  ## Module attributes

  - `@default_socket` — `/var/run/docker.sock` (WSL2: `/mnt/wsl/shared-docker/docker.sock`)
  - `@profile` — `:flame_docker` (dedicated `:httpc` profile; do not share with other HTTP clients)
  - `@docker_api_version` — `"v1.43"`

  ## To implement — profile

  - `start_profile/1` — `:inets.start(:httpc, profile: @profile)`, handle `:already_started`, call `configure_profile/1`
  - `stop_profile/0` — `:inets.stop(:httpc, @profile)`, rescue errors, return `:ok`
  - `configure_profile/1` (private) — `:httpc.set_options([{:unix_socket, charlist}, {:ipfamily, :local}], @profile)`

  ## To implement — HTTP core

  - `request/3` (private) — URL `http://localhost/<api_version><path>`; Jason-encode map bodies; `:httpc.request/4` with `@profile`; charlists for `:httpc`
  - `handle_response/2` (private) — 2xx → `{:ok, nil | map()}`; else `{:error, {:docker_error, status, body}}`

  ## To implement — public API

  - `version/0` — `GET /version`
  - `create_container/2` — `POST /containers/create?name=<URI.encode(name)>`; returns `{:ok, %{"Id" => id}}`
  - `start_container/1` — `POST /containers/{id}/start`; 204 and 304 → `:ok`
  - `stop_container/2` — `POST /containers/{id}/stop?t={timeout}`; 304 and 404 → `:ok`
  - `remove_container/2` — `DELETE /containers/{id}?force=&v=`; 404 → `:ok`
  - `inspect_container/1` — `GET /containers/{id}/json`
  - `stop_and_remove_container/2` — stop then `remove_container(id, force: true)`; idempotent

  ## Integration

  - Call `start_profile/1` from `FlameDockerBackend.init/1` (socket from `:docker_socket` config)
  - `create_container/2` receives the merged body from `build_create_body/1`; do not merge HostConfig here
  - Cleanup paths use `stop_and_remove_container/2` (see `docs/PLAN.md` §3)

  ## Verify

  ```
  mix test --only docker
  DOCKER_SOCKET=/var/run/docker.sock mix test --only docker
  ```

  Full step-by-step: `docs/DOCKER_API_CLIENT_IMPLEMENTATION.md`
  """

  @default_socket "/var/run/docker.sock"
  @profile :flame_docker
  @docker_api_version "v1.43"
end
