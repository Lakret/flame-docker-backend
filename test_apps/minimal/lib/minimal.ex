defmodule Minimal do
  @moduledoc """
  Example of a minimal app that uses FLAME with FLAMEDockerBackend.
  """

  def test_flame_backend_lambda(timeout \\ 10_000) do
    FLAME.call(
      Minimal.Runner,
      fn ->
        Process.sleep(1_000)
        :rand.uniform()
      end,
      timeout: timeout
    )
  end
end
