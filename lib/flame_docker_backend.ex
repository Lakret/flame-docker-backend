defmodule FlameDockerBackend do
  @moduledoc """
  Docker-out-of-Docker backend for [FLAME](https://github.com/phoenixframework/flame).
  """

  @behaviour FLAME.Backend

  defstruct [
    # Application name
    :app,
    # Docker image to use for runners
    :image,
    # Docker network to connect Parent with Runners
    :network,
    # Env vars to set on the runner node.
    # `PHX_SERVER=false` and `FLAME_PARENT` (with encoded parent info) env vars will be automatically added to this map.
    # `ERL_AFLAGS` and `ERL_ZFLAGS` will be copied from the Parent node and passed here too, if not explicitly defined.
    :env,
    # Are we running with Kamal 2?
    :is_kamal,
    # Environment variable used to lookup Runner's node hostaname for node's longname. Defaults to "HOSTNAME".
    :runner_hostname_env,
    # Auto-generated runner container name / runner node basename (part of the node name before '@')
    :runner_node_base,
    # Auto-inferred Parent hostname
    :parent_hostname,
    # Auto-created Parent reference
    :parent_ref
  ]

  @impl true
  def init(opts) do
    [app, parent_hostname] = node() |> to_string() |> String.split("@")
    default_opts = %__MODULE__{app: app, env: %{}, runner_hostname_env: "HOSTNAME", parent_hostname: parent_hostname}

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

    env = %{"PHX_SERVER" => "false", "FLAME_PARENT" => encoded_parent} |> Map.merge(state.env) |> add_erl_flags()

    state = %{state | env: env, parent_ref: parent_ref}
    {:ok, state}
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
end
