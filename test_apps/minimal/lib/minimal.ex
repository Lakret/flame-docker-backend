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

  def test_flame_backend_mfa() do
    FLAME.call(Minimal.Runner, {Minimal, :test_flame_backend_lambda, []})
  end
end
