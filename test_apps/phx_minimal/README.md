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

- **Added [`compile` to the `assets.deploy` alias](./mix.exs)** — Phoenix 1.8 colocated JS hooks are generated at compile time; esbuild needs them before bundling.

- **Tuned [prod `runtime.exs`](./config/runtime.exs) for local Docker** — the default `phx.new` prod URL is `https://example.com:443`, which makes Phoenix reject LiveView socket origins from `http://localhost:4000`. Defaults are now `PHX_HOST=localhost`, `PORT=4000`, `PHX_URL_SCHEME=http`.

- **Added [Dockerfile](./Dockerfile)** — layer order follows the [Phoenix containers guide](https://phoenix.hexdocs.pm/releases.html#containers) so deps, tailwind/esbuild setup, and compilation stay cached when only app code or assets change.

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

## Production

Build the release image from the repo root:

```bash
docker build -t phx_minimal:latest -f test_apps/phx_minimal/Dockerfile .
```

Create a user-defined network so parent and FLAME runner containers can resolve each other by name:

```bash
docker network create phx_minimal_flame_docker_backend_test
```

Run the parent container. Mount the host Docker socket and pass runtime configuration via environment variables (see [Phoenix deployment docs](https://phoenix.hexdocs.pm/releases.html#containers)):

```bash
docker run --rm \
  --name phx_minimal-parent \
  --network phx_minimal_flame_docker_backend_test \
  -p 4000:4000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e DATABASE_PATH=/app/phx_minimal.db \
  -e PHX_HOST=localhost \
  -e PHX_URL_SCHEME=http \
  -e PORT=4000 \
  phx_minimal:latest
```

Mount the correct Docker socket for your platform:

- on Linux: `-v /var/run/docker.sock:/var/run/docker.sock`
- on WSL2: `-v /mnt/wsl/shared-docker/docker.sock:/var/run/docker.sock`
- on macOS: `-v ~/.docker/run/docker.sock:/var/run/docker.sock`

`./config/runtime.exs` sets the FLAME image and network. Override at runtime if needed:

- `FLAME_IMAGE` (default: `phx_minimal:latest`)
- `FLAME_NETWORK` (default: `phx_minimal_flame_docker_backend_test`)

Behind HTTPS in a real deployment, set `PHX_HOST` to your public hostname and `PHX_URL_SCHEME=https` (and `PORT=443` if the endpoint URL should use port 443). Phoenix checks LiveView/WebSocket origins against `url: [host:, port:, scheme:]` in prod — the host/scheme/port must match what the browser uses.

Required runtime environment variables:

| Variable | Purpose |
|----------|---------|
| `SECRET_KEY_BASE` | Signs cookies and session data |
| `DATABASE_PATH` | SQLite database file path |
| `PHX_HOST` | Public hostname for URL generation and origin checks |
| `PHX_URL_SCHEME` | `http` for local Docker, `https` behind TLS |
| `PORT` | HTTP listen port (default: `4000`) |

`PHX_SERVER=true` and `DATABASE_PATH` defaults are set in the [Dockerfile](./Dockerfile). The release reads [runtime.exs](./config/runtime.exs) on startup, so changing host/scheme/secrets does not require rebuilding assets — only `docker build` again if Elixir or frontend code changed.
