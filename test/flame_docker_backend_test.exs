defmodule FLAMEDockerBackendTest do
  use ExUnit.Case, async: true

  alias FLAMEDockerBackend

  describe "init/1" do
    test "returns error when image is missing" do
      assert {:error, {:missing_config, :image}} = FLAMEDockerBackend.init(network: "net")
    end

    test "returns error when network is missing" do
      assert {:error, {:missing_config, :network}} = FLAMEDockerBackend.init(image: "img:latest")
    end

    test "rejects unknown config keys" do
      assert {:error, [:unknown]} =
               FLAMEDockerBackend.init(image: "img:latest", network: "net", unknown: true)
    end

    test "user can override PHX_SERVER but not FLAME_PARENT" do
      {:ok, state} =
        FLAMEDockerBackend.init(
          image: "img:latest",
          network: "net",
          env: %{"PHX_SERVER" => "true", "FLAME_PARENT" => "evil"}
        )

      assert state.env["PHX_SERVER"] == "true"
      assert state.env["FLAME_PARENT"] != "evil"
      assert is_binary(state.env["FLAME_PARENT"])
    end

    test "defaults PHX_SERVER to false" do
      {:ok, state} = FLAMEDockerBackend.init(image: "img:latest", network: "net")
      assert state.env["PHX_SERVER"] == "false"
    end
  end
end
