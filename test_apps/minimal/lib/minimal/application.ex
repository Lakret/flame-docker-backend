defmodule Minimal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {FLAME.Pool, name: Minimal.Runner, backend: FlameDockerBackend, min: 0, max: 2, idle_shutdown_after: 15_000}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Minimal.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
