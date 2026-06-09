defmodule FlameDockerBackend do
  @moduledoc """
  Docker-out-of-Docker backend for [FLAME](https://github.com/phoenixframework/flame).
  """
  require Logger
  alias FlameDockerBackend.DockerAPI

  @behaviour FLAME.Backend

  defstruct [
    # TODO: can this be inferred automatically?
    # Application name
    :app,
    # TODO: can we capture this from the Docker API and set to the current image by default?
    # Docker image to use for runners
    :image,
    # Docker network to connect Parent with Runners
    :network,
    # Env vars to set on the runner node.
    # `PHX_SERVER=false` and `FLAME_PARENT` (with encoded parent info) env vars will be automatically added to this map.
    # `ERL_AFLAGS` and `ERL_ZFLAGS` will be copied from the Parent node and passed here too, if not explicitly defined.
    :env,
    # Docker HostConfig map for runner containers (resource limits, binds, etc.).
    :host_config,
    # Top-level Docker Mounts list for runner containers.
    :mounts,
    # Docker Cmd override for runner containers (list of strings).
    :cmd,
    # Path to the Docker API Unix socket. This socket needs to be mounted into the Parent's docker container.
    # If not provided, a default value based on the operating system will be used.
    :docker_socket_path,
    # Debug option for not removing failed Runner containers.
    :keep_failed_runners,
    # How long to wait for the Runner to boot, in milliseconds. Defaults to 30 seconds.
    :boot_timeout,
    # Environment variable used to lookup Runner's node hostaname for node's longname. Defaults to "HOSTNAME".
    :runner_hostname_env,
    ##
    ## Data setup during Runner's `init`
    ##
    # Auto-generated runner container name / runner node basename (part of the node name before '@')
    :runner_node_base,
    # Auto-inferred Parent hostname
    :parent_hostname,
    # Auto-created Parent reference
    :parent_ref,
    ##
    ## Data received on Runner's successful boot
    ##
    # Docker container_id of the Runner
    :runner_container_id,
    # PID of the remote Terminator process
    :remote_terminator_pid,
    # Full Runner node name
    :runner_node_name
  ]

  @type t() :: %__MODULE__{
          app: String.t(),
          image: String.t(),
          network: String.t(),
          env: map() | nil,
          host_config: map() | nil,
          mounts: list() | nil,
          cmd: [String.t()] | nil,
          docker_socket_path: String.t() | nil,
          keep_failed_runners: bool() | nil,
          boot_timeout: pos_integer(),
          runner_hostname_env: String.t() | nil,
          runner_node_base: String.t() | nil,
          parent_hostname: String.t() | nil,
          parent_ref: reference() | nil,
          runner_container_id: String.t() | nil,
          remote_terminator_pid: pid() | nil,
          runner_node_name: node() | nil
        }

  @impl true
  @spec init(Keyword.t()) :: {:ok, t()}
  def init(opts) do
    [app, parent_hostname] = node() |> to_string() |> String.split("@")

    default_opts = %__MODULE__{
      app: app,
      env: %{},
      keep_failed_runners: false,
      boot_timeout: 30_000,
      runner_hostname_env: "HOSTNAME",
      parent_hostname: parent_hostname
    }

    conf = Application.get_env(:flame, __MODULE__) || []
    # TODO: Keyword.validate! to make sure that we don't allow breaking the struct by passing non-existing fields
    opts = Keyword.merge(conf, opts) |> Map.new()
    state = Map.merge(default_opts, opts)

    runner_node_base = "#{state.app}-flame-#{rand_id(20)}"
    state = %{state | runner_node_base: runner_node_base}

    parent_ref = make_ref()

    encoded_parent =
      FLAME.Parent.new(parent_ref, self(), __MODULE__, state.runner_node_base, state.runner_hostname_env)
      |> FLAME.Parent.encode()

    # TODO: do we need to do this here? it works without it, but maybe we should specify how to set Erlang Node name
    # manually if something goes wrong, e.g.:
    # Set `ERL_FLAGS=--name <runner_node_base>@<container_name>` on the runner.
    env = %{"PHX_SERVER" => "false", "FLAME_PARENT" => encoded_parent} |> Map.merge(state.env) |> add_erl_flags()

    state = %{state | env: env, parent_ref: parent_ref}
    {:ok, state}
  end

  @impl true
  @spec remote_boot(t()) :: {:ok, pid(), t()} | {:error, any()}
  def remote_boot(%__MODULE__{parent_ref: parent_ref} = state) do
    with {:ok, _httpc_profile_pid} <- DockerAPI.init(state.docker_socket_path),
         {:ok, _version} <- DockerAPI.version(),
         :ok <- maybe_pull_image(state.image),
         {:ok, runner_container_id} <- DockerAPI.create_container(build_create_body(state)),
         :ok <- DockerAPI.start_container(runner_container_id) do
      receive do
        {^parent_ref, {:remote_up, remote_terminator_pid}} ->
          state = %{
            state
            | runner_container_id: runner_container_id,
              remote_terminator_pid: remote_terminator_pid,
              runner_node_name: node(remote_terminator_pid)
          }

          {:ok, remote_terminator_pid, state}
      after
        state.boot_timeout ->
          Logger.error("Didn't receive terminator pid from the Runner container after #{state.boot_timeout} ms.")

          if not state.keep_failed_runners do
            result = DockerAPI.stop_and_remove_container(runner_container_id)
            Logger.info("Removal of failed Runner via Docker API: #{inspect(result)}.")
          end

          {:error, :timeout}
      end
    end
  end

  @impl true
  @spec remote_spawn_monitor(t(), {atom(), atom(), list()} | (-> any())) :: {:ok, {pid(), reference()}}
  def remote_spawn_monitor(state, func)

  def remote_spawn_monitor(%__MODULE__{} = state, {mod, fun, args})
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    {pid, ref} = Node.spawn_monitor(state.runner_node_name, mod, fun, args)
    {:ok, {pid, ref}}
  end

  def remote_spawn_monitor(%__MODULE__{} = state, func) when is_function(func, 0) do
    {pid, ref} = Node.spawn_monitor(state.runner_node_name, func)
    {:ok, {pid, ref}}
  end

  @impl true
  @spec system_shutdown() :: :ok
  def system_shutdown() do
    System.stop()
  end

  @doc false
  @spec rand_id(pos_integer()) :: binary()
  def rand_id(len) when is_integer(len) and len > 0 do
    len
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
    |> binary_part(0, len)
  end

  @doc false
  @spec add_erl_flags(map()) :: map()
  def add_erl_flags(env) do
    env =
      if flags = System.get_env("ERL_AFLAGS") do
        Map.put_new(env, "ERL_AFLAGS", flags)
      else
        env
      end

    if flags = System.get_env("ERL_ZFLAGS") do
      Map.put_new(env, "ERL_ZFLAGS", flags)
    else
      env
    end
  end

  @spec build_create_body(t()) :: map()
  defp build_create_body(%__MODULE__{} = state) do
    %{
      "Hostname" => state.runner_node_base,
      "name" => state.runner_node_base,
      "Image" => state.image,
      "Env" => state.env |> Map.to_list() |> Enum.map(fn {k, v} -> "#{k}=#{v}" end),
      "NetworkingConfig" => %{"EndpointsConfig" => %{state.network => %{}}}
    }
    |> maybe_put_create_field("HostConfig", state.host_config)
    |> maybe_put_create_field("Cmd", state.cmd)
    |> maybe_put_create_field("Mounts", state.mounts)
  end

  @spec maybe_put_create_field(map(), String.t(), term()) :: map()
  defp maybe_put_create_field(body, _key, nil), do: body
  defp maybe_put_create_field(body, key, value), do: Map.put(body, key, value)

  @spec maybe_pull_image(String.t()) :: :ok | {:error, any()}
  defp maybe_pull_image(image) do
    if DockerAPI.image_exists?(image) do
      Logger.debug("Image #{image} already present, skipping pull")
      :ok
    else
      Logger.info("Pulling image #{image}")

      case DockerAPI.pull_image(%{"fromImage" => image}) do
        {:ok, _events} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
