defmodule PhxMinimal.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {FLAME.Pool,
       name: PhxMinimal.Runner,
       backend: FlameDockerBackend,
       min: 0,
       max: 2,
       idle_shutdown_after: 15_000,
       boot_timeout: 30_000},
      PhxMinimalWeb.Telemetry,
      PhxMinimal.Repo,
      {Ecto.Migrator, repos: Application.fetch_env!(:phx_minimal, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:phx_minimal, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhxMinimal.PubSub},
      PhxMinimalWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: PhxMinimal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhxMinimalWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
