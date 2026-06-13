defmodule PhxMinimalWeb.FlameDemoLive do
  use PhxMinimalWeb, :live_view

  alias PhxMinimal.Colors
  alias PhxMinimal.Colors.FlameColor

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       colors: Colors.list_flame_colors(),
       pending: 0,
       latest: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center gap-8">
        <div class="space-y-2 text-center">
          <h1 class="text-3xl font-bold tracking-tight">FLAME Docker Demo</h1>
          <p class="text-base-content/70 max-w-md">
            Each click runs a remote task on a Docker runner via FLAMEDockerBackend.
            Completed colors are saved to the database.
          </p>
        </div>

        <button
          id="spawn-flame"
          type="button"
          phx-click="spawn"
          class="btn btn-lg btn-primary min-w-56 transition-all duration-500"
          style={button_style(@latest)}
        >
          Spawn FLAME task
          <span :if={@pending > 0} class="badge badge-neutral ml-2">{@pending}</span>
        </button>

        <div
          :if={@latest}
          id="color-panel"
          class="w-full max-w-lg aspect-[5/3] rounded-3xl shadow-2xl transition-all duration-700 flex flex-col items-center justify-center gap-3 p-6"
          style={"background-color: #{@latest.color}"}
        >
          <span class="text-2xl font-mono font-bold" style={"color: #{contrasting_text(@latest.color)}"}>
            {@latest.color}
          </span>
          <span class="text-sm opacity-90" style={"color: #{contrasting_text(@latest.color)}"}>
            generated on {@latest.runner_node}
          </span>
        </div>

        <div :if={@colors != []} class="w-full max-w-lg space-y-3">
          <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide">
            Saved colors
          </h2>
          <ul id="flame-colors" class="grid grid-cols-4 sm:grid-cols-6 gap-2">
            <li :for={color <- @colors} id={"flame-color-#{color.id}"}>
              <div
                class="aspect-square rounded-lg ring-2 ring-base-content/10 shadow-sm transition-transform hover:scale-110"
                style={"background-color: #{color.color}"}
                title={"#{color.color} · #{color.runner_node}"}
              />
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("spawn", _params, socket) do
    ref = make_ref()

    {:noreply,
     socket
     |> update(:pending, &(&1 + 1))
     |> start_async(ref, fn -> PhxMinimal.spawn_flame_color() end)}
  end

  @impl true
  def handle_async(_ref, {:ok, %{color: color, node: runner_node}}, socket) do
    flame_color =
      Colors.create_flame_color!(%{
        color: color,
        runner_node: to_string(runner_node)
      })

    {:noreply,
     socket
     |> update(:pending, &max(&1 - 1, 0))
     |> update(:colors, fn colors -> [flame_color | colors] |> Enum.take(50) end)
     |> assign(:latest, flame_color)}
  end

  def handle_async(_ref, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> update(:pending, &max(&1 - 1, 0))
     |> put_flash(:error, "FLAME task failed: #{inspect(reason)}")}
  end

  defp button_style(%FlameColor{color: color}), do: "background-color: #{color}; border-color: #{color}"
  defp button_style(_), do: nil

  defp contrasting_text("#" <> hex) do
    r = String.slice(hex, 0, 2) |> String.to_integer(16)
    g = String.slice(hex, 2, 2) |> String.to_integer(16)
    b = String.slice(hex, 4, 2) |> String.to_integer(16)

    if 0.299 * r + 0.587 * g + 0.114 * b > 160, do: "#111", else: "#fff"
  end
end
