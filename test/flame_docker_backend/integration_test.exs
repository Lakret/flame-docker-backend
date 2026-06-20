defmodule FLAMEDockerBackend.IntegrationTest do
  use ExUnit.Case, async: false

  alias FLAMEDockerBackend.DockerAPI
  alias FLAMEDockerBackend.DockerIntegration

  @moduletag :docker
  @moduletag timeout: 300_000

  setup_all do
    DockerIntegration.ensure_docker!()
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
    @memory_limit 64_000_000

    setup context do
      DockerIntegration.ensure_image!(:minimal)

      suffix = FLAMEDockerBackend.rand_id(8)
      host_config = %{"Memory" => @memory_limit}
      ctx = DockerIntegration.start_parent!(:minimal, suffix, host_config: host_config)

      on_exit(fn -> DockerIntegration.cleanup!(ctx) end)

      Map.merge(context, Map.put(ctx, :memory_limit, @memory_limit))
    end

    test "FLAME.call provisions a runner with host_config and removes it after idle shutdown", %{
      parent_name: parent_name,
      app: app,
      memory_limit: memory_limit
    } do
      assert DockerIntegration.runner_containers(app) == []

      output = DockerIntegration.exec_rpc!(parent_name, app)
      assert output =~ ~r/\d/

      runner_id = DockerIntegration.wait_for_runner!(app)
      assert {:ok, info} = DockerAPI.inspect_container(runner_id)
      assert info["HostConfig"]["Memory"] == memory_limit

      DockerIntegration.wait_for_no_runners!(app)
      assert DockerIntegration.runner_containers(app) == []
    end
  end

  describe "phx_minimal test app" do
    setup context do
      DockerIntegration.ensure_image!(:phx_minimal)

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
