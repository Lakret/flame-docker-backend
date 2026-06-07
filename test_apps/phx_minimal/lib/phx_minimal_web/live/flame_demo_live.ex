defmodule PhxMinimalWeb.FlameDemoLive do
  use PhxMinimalWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, status: :idle, result: nil, history: [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center gap-8">
        <div class="space-y-2 text-center">
          <h1 class="text-3xl font-bold tracking-tight">FLAME Docker Demo</h1>
          <p class="text-base-content/70 max-w-md">
            Each click spawns a remote task on a Docker runner via FlameDockerBackend.
            The runner picks a random color and sends it back.
          </p>
        </div>

        <button
          id="spawn-flame"
          type="button"
          phx-click="spawn"
          disabled={@status == :loading}
          class={[
            "btn btn-lg min-w-56 transition-all duration-500",
            @status == :loading && "btn-disabled animate-pulse",
            @status != :loading && "btn-primary"
          ]}
          style={button_style(@result, @status)}
        >
          <%= spawn_label(@status) %>
        </button>

        <div
          :if={@result}
          id="color-panel"
          class="w-full max-w-lg aspect-[5/3] rounded-3xl shadow-2xl transition-all duration-700 flex flex-col items-center justify-center gap-3 p-6"
          style={"background-color: #{@result.color}"}
        >
          <span class="text-2xl font-mono font-bold" style={"color: #{contrasting_text(@result.color)}"}>
            {@result.color}
          </span>
          <span class="text-sm opacity-90" style={"color: #{contrasting_text(@result.color)}"}>
            generated on {@result.node}
          </span>
        </div>

        <div :if={@history != []} class="flex flex-wrap justify-center gap-2">
          <div
            :for={{color, index} <- Enum.with_index(@history)}
            id={"history-#{index}"}
            class="size-10 rounded-lg ring-2 ring-base-content/10 shadow-sm transition-transform hover:scale-110"
            style={"background-color: #{color}"}
            title={color}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("spawn", _params, socket) do
    {:noreply,
     socket
     |> assign(:status, :loading)
     |> start_async(:flame_color, fn -> PhxMinimal.spawn_flame_color() end)}
  end

  @impl true
  def handle_async(:flame_color, {:ok, result}, socket) do
    history = Enum.take([result.color | socket.assigns.history], 12)

    {:noreply,
     socket
     |> assign(status: :done, result: result, history: history)}
  end

  def handle_async(:flame_color, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:status, :idle)
     |> put_flash(:error, "FLAME task failed: #{inspect(reason)}")}
  end

  defp spawn_label(:loading), do: "Spawning on remote runner…"
  defp spawn_label(:done), do: "Spawn another FLAME task"
  defp spawn_label(_), do: "Spawn FLAME task"

  defp button_style(%{color: color}, :done), do: "background-color: #{color}; border-color: #{color}"
  defp button_style(_, _), do: nil

  defp contrasting_text("#" <> hex) do
    r = String.slice(hex, 0, 2) |> String.to_integer(16)
    g = String.slice(hex, 2, 2) |> String.to_integer(16)
    b = String.slice(hex, 4, 2) |> String.to_integer(16)

    if 0.299 * r + 0.587 * g + 0.114 * b > 160, do: "#111", else: "#fff"
  end
end
