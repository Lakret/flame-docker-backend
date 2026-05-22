defmodule FlameDockerBackendTest do
  use ExUnit.Case
  doctest FlameDockerBackend

  test "greets the world" do
    assert FlameDockerBackend.hello() == :world
  end
end
