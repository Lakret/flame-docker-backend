defmodule FLAMEDockerBackend.DockerAPI do
  @moduledoc """
  Thin wrapper over Docker Engine API via Unix socket.

  Transport only — sends JSON bodies as-is. `FLAMEDockerBackend` builds
  the container create payloads; this module just relays them to Docker.

  Uses OTP `:httpc` with a dedicated profile (`:flame_docker`) to isolate
  it from other `:httpc` users in the same BEAM.

  ## Setup

  Call `init/1` once before any other function — typically from
  `FLAMEDockerBackend.init/1`.

  On WSL2, pass the socket path explicitly:

      DockerAPI.init("/mnt/wsl/shared-docker/docker.sock")

  On macOS, Docker socket is mounted in user directory:

      Path.join(System.user_home(), ".docker/run/docker.sock")
      |> DockerAPI.init()

  ## Workflow

  Full round-trip — requires Docker to be running and `init/1` called first:

      iex> alias FLAMEDockerBackend.DockerAPI
      FLAMEDockerBackend.DockerAPI
      iex> {:ok, _pid} = DockerAPI.init()
      iex> {:ok, _version} = DockerAPI.version()
      iex> {:ok, _events} = DockerAPI.pull_image(%{"fromImage" => "hello-world"})
      iex> {:ok, id} = DockerAPI.create_container(%{"name" => "doctest-workflow", "Image" => "hello-world"})
      iex> is_binary(id)
      true
      iex> DockerAPI.start_container(id)
      :ok
      iex> {:ok, info} = DockerAPI.inspect_container(id)
      iex> info["Name"]
      "/doctest-workflow"
      iex> DockerAPI.stop_and_remove_container(id)
      :ok

  """
  require Logger

  @profile :flame_docker
  @docker_api_version "v1.45"
  @prefix "http://localhost/#{@docker_api_version}"

  @doc """
  Initializes the `:httpc` profile for Unix socket communication with Docker.

  Idempotent — safe to call when the profile is already running.
  """
  @spec init(String.t() | nil) :: {:ok, pid()} | {:error, any()}
  def init(socket \\ nil) do
    socket = socket || default_socket_path()
    socket_cl = String.to_charlist(socket)

    with {:ok, _} <- Application.ensure_all_started(:inets) do
      case :inets.start(:httpc, profile: @profile) do
        {:ok, pid} ->
          :ok = :httpc.set_options([unix_socket: socket_cl, ipfamily: :local], @profile)
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          :ok = :httpc.set_options([unix_socket: socket_cl, ipfamily: :local], @profile)
          {:ok, pid}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns the Docker API version string reported by the daemon.
  """
  @spec version() :: {:ok, String.t()} | {:error, any()}
  def version() do
    with {:ok, %{"ApiVersion" => version}} <- :httpc.request(~c"http://localhost/version", @profile) |> decode_resp() do
      {:ok, version}
    end
  end

  @doc """
  Lists containers.

  Options:
  - `:all` — include stopped containers (default `false`)
  - `:filters` — Docker filters map, e.g. `%{"name" => ["minimal-flame"]}`
  """
  @spec list_containers(keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_containers(opts \\ []) do
    all = if Keyword.get(opts, :all, false), do: "1", else: "0"
    filters = Keyword.get(opts, :filters)

    params = %{"all" => all}
    params = if filters, do: Jason.encode!(filters) |> then(fn x -> Map.put(params, "filters", x) end), else: params
    get("/containers/json?#{URI.encode_query(params)}") |> decode_resp()
  end

  @doc """
  Checks if an image exists locally.
  """
  @spec image_exists?(String.t()) :: boolean()
  def image_exists?(image) when is_binary(image) do
    case get("/images/#{URI.encode_www_form(image)}/json") do
      {:ok, {{_, 200, _}, _, _}} -> true
      _ -> false
    end
  end

  @doc """
  Pulls `fromImage` from a registry.

  Accepts any `POST /images/create` query parameters as map keys;
  `"tag"` defaults to `"latest"`. Returns the list of JSON progress-event
  maps streamed by Docker during the pull.
  """
  @spec pull_image(map()) :: {:ok, [map()]} | {:error, any()}
  def pull_image(%{"fromImage" => from_image} = params) when is_binary(from_image) do
    tag = Map.get(params, "tag", "latest")

    post("#{@prefix}/images/create?fromImage=#{URI.encode(from_image)}&tag=#{URI.encode(tag)}", nil)
    |> decode_resp(true)
  end

  @doc """
  Creates a container named `params["name"]` using the given Docker API body.

  Returns `{:ok, id}` where `id` is the full container ID.
  """
  @spec create_container(map()) :: {:ok, String.t()} | {:error, any()}
  def create_container(%{"name" => name} = params) when is_binary(name) do
    with {:ok, %{"Id" => id}} <- post("#{@prefix}/containers/create?name=#{URI.encode(name)}", params) |> decode_resp() do
      {:ok, id}
    end
  end

  @doc """
  Starts a container. Treats 304 (already running) as success.
  """
  @spec start_container(String.t()) :: :ok | {:error, any()}
  def start_container(id) do
    case post("#{@prefix}/containers/#{id}/start", nil) do
      {:ok, {{_, status, _}, _, _}} when status in [204, 304] ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:docker_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, {:httpc_error, reason}}
    end
  end

  @doc """
  Stops a container.

  Treats 304 (already stopped) and 404 (not found) as success, making this
  safe to call on already-stopped or missing containers. `timeout` is the
  number of seconds Docker waits before killing; defaults to 10.
  """
  @spec stop_container(String.t(), non_neg_integer()) :: :ok | {:error, any()}
  def stop_container(id, timeout \\ 10) do
    case post("#{@prefix}/containers/#{id}/stop?t=#{timeout}", nil) do
      {:ok, {{_, status, _}, _, _}} when status in [204, 304, 404] ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:docker_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, {:httpc_error, reason}}
    end
  end

  @doc """
  Removes a container. Treats 404 (not found) as success.

  Options:
  - `:force` — kill and remove a running container (default `false`)
  - `:volumes` — also remove anonymous volumes attached to the container (default `false`)
  """
  @spec remove_container(String.t(), keyword()) :: :ok | {:error, any()}
  def remove_container(id, opts \\ []) do
    force = if Keyword.get(opts, :force, false), do: "1", else: "0"
    volumes = if Keyword.get(opts, :volumes, false), do: "1", else: "0"

    case delete("/containers/#{id}?force=#{force}&v=#{volumes}") do
      {:ok, {{_, status, _}, _, _}} when status in [204, 404] ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:docker_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, {:httpc_error, reason}}
    end
  end

  @doc """
  Returns the full Docker API JSON object for the given container ID.
  """
  @spec inspect_container(String.t()) :: {:ok, map()} | {:error, any()}
  def inspect_container(id) do
    get("/containers/#{id}/json") |> decode_resp()
  end

  @doc """
  Stops, then forcefully removes a container.

  Idempotent — safe to call on already-stopped, already-removed, or
  missing containers. `timeout` is forwarded to `stop_container/2`.
  """
  @spec stop_and_remove_container(String.t(), non_neg_integer()) :: :ok | {:error, any()}
  def stop_and_remove_container(id, timeout \\ 10) do
    with :ok <- stop_container(id, timeout) do
      remove_container(id, force: true)
    end
  end

  ## API only used in Integration Tests

  @doc """
  Creates a user-defined bridge network. Treats name conflict as success.
  Only used in tests.
  """
  @spec create_network(String.t()) :: :ok | {:error, any()}
  def create_network(name) when is_binary(name) do
    case post("#{@prefix}/networks/create", %{"Name" => name, "CheckDuplicate" => true}) |> decode_resp() do
      {:ok, _} ->
        :ok

      {:error, {:docker_error, 409, _}} ->
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Removes a network. Treats 404 as success.
  Only used in tests.
  """
  @spec remove_network(String.t()) :: :ok | {:error, any()}
  def remove_network(name) when is_binary(name) do
    case delete("/networks/#{URI.encode(name)}") do
      {:ok, {{_, status, _}, _, _}} when status in [204, 404] ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:docker_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, {:httpc_error, reason}}
    end
  end

  @doc false
  @spec network_exists?(String.t()) :: boolean()
  def network_exists?(name) when is_binary(name) do
    case get("/networks/#{URI.encode(name)}") do
      {:ok, {{_, 200, _}, _, _}} -> true
      _ -> false
    end
  end

  @doc """
  Builds an image via the `docker build` CLI.
  Only used in tests.

  The HTTP build API is stream-heavy, so the CLI is used.
  """
  @spec build_image(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def build_image(tag, dockerfile, context_dir)
      when is_binary(tag) and is_binary(dockerfile) and is_binary(context_dir) do
    case System.cmd("docker", ["build", "-t", tag, "-f", dockerfile, context_dir], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {:docker_cli, code, output}}
    end
  end

  @doc """
  Runs `docker exec` against a container name or ID.
  Only used in tests.
  """
  @spec exec(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, any()}
  def exec(container, args) when is_binary(container) and is_list(args) do
    case System.cmd("docker", ["exec", container | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, code} -> {:error, {:docker_cli, code, output}}
    end
  end

  ## Helpers

  @doc false
  def default_socket_path() do
    mac_os_default_path = System.get_env("HOME") |> Path.join(".docker/run/docker.sock")

    cond do
      # WSL2 (mount point present)
      File.exists?("/mnt/wsl/shared-docker/docker.sock") ->
        "/mnt/wsl/shared-docker/docker.sock"

      # macOS (Docker Desktop sometimes uses user home run dir)
      File.exists?(mac_os_default_path) ->
        mac_os_default_path

      # Default: Linux and Docker Desktop
      true ->
        "/var/run/docker.sock"
    end
  end

  @doc false
  def get(path) do
    :httpc.request(:get, {String.to_charlist("#{@prefix}#{path}"), []}, [], [], @profile)
  end

  @doc false
  defp delete(path) do
    :httpc.request(:delete, {String.to_charlist("#{@prefix}#{path}"), []}, [], [], @profile)
  end

  @doc false
  @spec post(String.t(), map() | nil, list()) :: {:ok, any()} | {:error, any()}
  def post(url, body, http_options \\ [])

  def post(url, nil, http_options) do
    :httpc.request(
      :post,
      {String.to_charlist(url), [], ~c"text/plain", ""},
      http_options,
      [],
      @profile
    )
  end

  def post(url, body, http_options) when is_map(body) do
    with {:ok, encoded} <- Jason.encode(body) do
      :httpc.request(
        :post,
        {String.to_charlist(url), [], ~c"application/json", String.to_charlist(encoded)},
        http_options,
        [],
        @profile
      )
    end
  end

  @doc false
  @spec decode_resp(any(), boolean()) :: {:ok, nil | map() | [map()]} | {:error, any()}
  def decode_resp(response, multiline \\ false)

  def decode_resp({:ok, {{_protocol, status_code, _status}, _headers, body}}, multiline) do
    case status_code do
      _ when status_code in [200, 201] ->
        if multiline do
          body
          |> to_string()
          |> String.split("\r\n", trim: true)
          |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
            case Jason.decode(line) do
              {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
              {:error, err} -> {:halt, {:error, %{"line" => line, "error" => err}}}
            end
          end)
          |> then(fn
            {:ok, acc} -> {:ok, Enum.reverse(acc)}
            err -> err
          end)
        else
          body |> to_string() |> Jason.decode()
        end

      204 ->
        {:ok, nil}

      _ ->
        {:error, {:docker_error, status_code, to_string(body)}}
    end
  end

  def decode_resp(err, _multiline), do: err
end
