# PhxMinimal

Phoenix app example of using FlameDockerBackend.
The app serves a simple LiveView UI that spawns a FLAME task on a remote Docker runner and visualizes the random color the runner returns.
Since the backend is Docker-specific, remote FLAME tasks only work when the app is running inside a Docker container.

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

- **Added `FLAME.Pool` child to the [application supervisor](./lib/phx_minimal/application.ex)**

  ```elixir
  @impl true
  def start(_type, _args) do
    children = [
      {FLAME.Pool, name: PhxMinimal.Runner, backend: FlameDockerBackend, min: 0, max: 2, idle_shutdown_after: 30_000},
      ...
    ]

    ...
  end
  ```

- **Added default configs.** See [./config/runtime.exs](./config/runtime.exs).

- **Added [PhxMinimal.spawn_flame_color/0](./lib/phx_minimal.ex)** — calls `FLAME.call/2` to run a function on a remote runner that sleeps briefly, picks a random hex color, and returns it with the runner node name.

- **Added [FlameDemoLive](./lib/phx_minimal_web/live/flame_demo_live.ex)** — replaces the default landing page. Clicking "Spawn FLAME task" runs `spawn_flame_color/0` via `start_async/3`, fills a color panel with the result, tints the button, and keeps a swatch history.

- **Updated [router](./lib/phx_minimal_web/router.ex)** — `live "/", FlameDemoLive` instead of the default `PageController` home action.

- **Added [Dockerfile](./Dockerfile).**

## Trying it Out

To see it in action, try `./scripts/phx_minimal/01_run.sh` from the repo's root.
Open [http://localhost:4000](http://localhost:4000) and click **Spawn FLAME task**.
Cleanup with `./scripts/phx_minimal/02_cleanup.sh`.

**Watch Docker activity** (in another terminal):

```bash
docker ps -a --filter "name=phx_minimal"
```

**Connect to a FLAME runner node:**

```bash
docker exec -it $CONTAINER_ID bin/phx_minimal remote
```
