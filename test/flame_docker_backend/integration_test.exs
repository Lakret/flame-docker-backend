defmodule FLAMEDockerBackend.IntegrationTest do
  use ExUnit.Case, async: false

  alias FLAMEDockerBackend.DockerAPI
  alias FLAMEDockerBackend.DockerIntegration

  @moduletag :docker
  @moduletag timeout: 300_000

  setup_all do
    DockerIntegration.ensure_docker!()
    DockerIntegration.ensure_image!(:minimal)
    DockerIntegration.ensure_image!(:phx_minimal)
    :ok
  end

  describe "DockerAPI network lifecycle" do
    test "creates and removes a network" do
      name = "flame_docker_backend_api_test_#{FLAMEDockerBackend.rand_id(8)}"

      assert :ok = DockerAPI.create_network(name)
      assert DockerAPI.network_exists?(name)
      assert :ok = DockerAPI.remove_network(name)
      refute DockerAPI.network_exists?(name)
    end
  end

  describe "minimal test app" do
    setup context do
      suffix = FLAMEDockerBackend.rand_id(8)
      ctx = DockerIntegration.start_parent!(:minimal, suffix)

      on_exit(fn -> DockerIntegration.cleanup!(ctx) end)

      Map.merge(context, ctx)
    end

    test "FLAME.call provisions a runner container and removes it after idle shutdown", %{
      parent_name: parent_name,
      app: app
    } do
      assert DockerIntegration.runner_containers(app) == []

      output = DockerIntegration.exec_rpc!(parent_name, app)
      assert output =~ ~r/\d/

      DockerIntegration.wait_for_no_runners!(app)
      assert DockerIntegration.runner_containers(app) == []
    end
  end

  describe "phx_minimal test app" do
    setup context do
      suffix = FLAMEDockerBackend.rand_id(8)
      ctx = DockerIntegration.start_parent!(:phx_minimal, suffix)

      on_exit(fn -> DockerIntegration.cleanup!(ctx) end)

      Map.merge(context, ctx)
    end

    test "FLAME.call provisions a runner container and removes it after idle shutdown", %{
      parent_name: parent_name,
      app: app
    } do
      assert DockerIntegration.runner_containers(app) == []

      output = DockerIntegration.exec_rpc!(parent_name, app)
      assert output =~ "#"
      assert output =~ "node:"

      DockerIntegration.wait_for_no_runners!(app)
      assert DockerIntegration.runner_containers(app) == []
    end
  end
end
