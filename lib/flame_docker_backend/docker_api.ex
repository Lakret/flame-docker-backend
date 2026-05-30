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
  require Logger

  # WSL2: /mnt/wsl/shared-docker/docker.sock
  @default_socket "/var/run/docker.sock"
  @profile :flame_docker
  @docker_api_version "v1.45"
  @prefix "http://localhost/#{@docker_api_version}"

  @doc """
  Initializes :httpc profile for connecting to the Docker API Unix `socket`.
  """
  @spec init(String.t()) :: {:ok, pid()} | {:error, any()}
  def init(socket \\ @default_socket) do
    socket = socket |> String.to_charlist()

    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, profile_pid} <- :inets.start(:httpc, profile: @profile),
         :ok <- :httpc.set_options([unix_socket: socket, ipfamily: :local], @profile) do
      {:ok, profile_pid}
    end
  end

  @doc false
  def decode_resp(response, multiline \\ false)

  def decode_resp(
        {:ok, {{_protocol, status_code, _status}, _headers, body} = resp},
        multiline
      ) do
    decoder =
      if multiline,
        do: fn body ->
          body
          |> to_string()
          |> String.split("\r\n", trim: true)
          |> Enum.reduce_while({:ok, []}, fn line, {:ok, prev_resp} ->
            case Jason.decode(line) do
              {:ok, resp} ->
                {:cont, {:ok, [resp | prev_resp]}}

              {:error, err} ->
                {:halt,
                 {:error, %{"line" => line, "jason_error" => err, "prev_resp" => prev_resp}}}
            end
          end)
          |> then(fn
            {:ok, resp} -> {:ok, Enum.reverse(resp)}
            x -> x
          end)
        end,
        else: fn body -> body |> to_string() |> Jason.decode() end

    case status_code do
      _ when status_code in [200, 201] -> decoder.(body)
      _ -> {:error, resp}
    end
  end

  def decode_resp(err, _multiline), do: err

  def post(url, body, http_options \\ [])

  def post(url, nil, http_options) do
    url = String.to_charlist(url) |> dbg
    :httpc.request(:post, {url, [], ~c"text/plain", ""}, http_options, [], @profile)
  end

  def post(url, body, http_options) when is_map(body) do
    with {:ok, body} <- Jason.encode(body) do
      body = String.to_charlist(body)
      url = String.to_charlist(url)
      :httpc.request(:post, {url, [], ~c"application/json", body}, http_options, [], @profile)
    end
  end

  @spec version() :: String.t()
  def version() do
    with {:ok, %{"ApiVersion" => version}} <-
           :httpc.request(~c"http://localhost/version", @profile) |> decode_resp() do
      {:ok, version}
    end
  end

  @doc """
  List containers
  """
  def ps() do
    :httpc.request(~c"#{@prefix}/containers/json", @profile)
    |> decode_resp()
  end

  def pull_image(%{"fromImage" => from_image} = params) do
    tag = Map.get(params, "tag", "latest")

    post("#{@prefix}/images/create?fromImage=#{from_image}&tag=#{tag}", nil)
    |> decode_resp(true)
    |> dbg
  end

  # `create_container/2` — `POST /containers/create?name=<URI.encode(name)>`; returns `{:ok, %{"Id" => id}}`
  def create_container(%{"name" => name} = params) when is_binary(name) do
    with {:ok, %{"Id" => id}} <-
           post("#{@prefix}/containers/create?name=#{URI.encode(name)}", params) |> decode_resp() do
      {:ok, id}
    end
  end

  # resp = DockerAPI.pull_image(%{"fromImage" => "hello-world"})
  # ~c"http://localhost/v1.45/images/create?fromImage=hello-world"
  # resp = DockerAPI.create_container(%{"name" => "test", "Image" => "hello-world"}
end
