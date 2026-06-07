# Minimal

Minimal app example of using FlameDockerBackend.
The app does nothing useful - it just tests that `FLAME.call` with our backend succeeds.
Since the backend is Docker-specific, this functionality only works when the app is running inside a Docker container.

## FLAME + FlameDockerBackend Integration Steps

To integrate FLAME with FlameDockerBackend, the default `mix phx.new --sup` skeleton was adopted like so:

- **Added [Mix dependencies](mix.exs).**

  ```elixir
  defp deps do
    [
      {:flame, "~> 0.5"},
      {:flame_docker_backend, path: "../../"}
    ]
  end
  ```

- **Added `FLAME.Pool` child to the [application supervisor](`./lib/minimal/application.ex`)**

  ```elixir
  @impl true
  def start(_type, _args) do
    children = [
      {FLAME.Pool, name: Minimal.Runner, backend: FlameDockerBackend, min: 0, max: 2, idle_shutdown_after: 30_000}
    ]

    ...
  end
  ```

- **Added default configs.** See [./config/config.exs](test_apps/minimal/config/config.exs)
and [./config/runtime.exs](test_apps/minimal/config/runtime.exs).

- **Added [Dockerfile](test_apps/minimal/Dockerfile).**

## Trying it Out

To see it in action, try `./scripts/minimal/01_run.sh` from the repo's root.
Cleanup with `./scripts/minimal/02_run.sh`.
