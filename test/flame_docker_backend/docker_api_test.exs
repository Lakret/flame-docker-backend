defmodule FlameDockerBackend.DockerAPITest do
  use ExUnit.Case, async: false

  @moduletag :docker

  doctest FlameDockerBackend.DockerAPI
end
