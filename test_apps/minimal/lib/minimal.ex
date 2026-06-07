defmodule Minimal do
  @moduledoc """
  Documentation for `Minimal`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Minimal.hello()
      :world

  """
  def hello do
    :world
  end


  def test_flame_backend_lambda() do
    FLAME.call(Minimal.Runner, fn ->
      Process.sleep(10_000)
      :rand.uniform()
    end)
  end
end
