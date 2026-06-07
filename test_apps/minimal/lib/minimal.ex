defmodule Minimal do
  @moduledoc """
  Example of a minimal app that uses FLAME with FlameDockerBackend.DockerAPI.
  """

  def test_flame_backend_lambda() do
    FLAME.call(Minimal.Runner, fn ->
      Process.sleep(10_000)
      :rand.uniform()
    end)
  end
end
