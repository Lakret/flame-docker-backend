defmodule PhxMinimal do
  @moduledoc """
  Phoenix app showcasing FLAME with FlameDockerBackend.
  """

  @type flame_color_result :: %{
          color: String.t(),
          node: node()
        }

  @spec spawn_flame_color() :: flame_color_result()
  def spawn_flame_color() do
    FLAME.call(PhxMinimal.Runner, fn ->
      Process.sleep(1_000)

      color =
        :rand.uniform(0xFFFFFF)
        |> Integer.to_string(16)
        |> String.pad_leading(6, "0")
        |> then(&("#" <> &1))

      %{color: color, node: node()}
    end)
  end
end
