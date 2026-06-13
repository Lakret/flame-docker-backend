defmodule FlameDockerBackend.DockerIntegration do
  @moduledoc false

  alias FlameDockerBackend.DockerAPI

  @repo_root Path.expand("../..", Path.dirname(__ENV__.file))
  @integration_cookie "flame_docker_backend_integration_test"

  @test_apps %{
    minimal: %{
      image: "minimal:latest",
      dockerfile: "test_apps/minimal/Dockerfile",
      network: "minimal_flame_docker_backend_integration",
      parent_name_prefix: "minimal-it-parent",
      runner_name_filter: "minimal-flame",
      release_bin: "bin/minimal",
      rpc: "IO.inspect(Minimal.test_flame_backend_lambda(120_000))"
    },
    phx_minimal: %{
      image: "phx_minimal:latest",
      dockerfile: "test_apps/phx_minimal/Dockerfile",
      network: "phx_minimal_flame_docker_backend_integration",
      parent_name_prefix: "phx-minimal-it-parent",
      runner_name_filter: "phx_minimal-flame",
      release_bin: "bin/phx_minimal",
      rpc: "IO.inspect(PhxMinimal.spawn_flame_color())"
    }
  }

  def repo_root, do: @repo_root

  def ensure_docker! do
    case DockerAPI.init() do
      {:ok, _} ->
        case DockerAPI.version() do
          {:ok, _} -> :ok
          {:error, reason} -> raise "Docker daemon unavailable: #{inspect(reason)}"
        end

      {:error, reason} ->
        raise "Docker socket unavailable: #{inspect(reason)}"
    end
  end

  def ensure_image!(app) when app in [:minimal, :phx_minimal] do
    %{image: image, dockerfile: dockerfile} = Map.fetch!(@test_apps, app)

    case DockerAPI.build_image(image, Path.join(@repo_root, dockerfile), @repo_root) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise "docker build #{image} failed: #{inspect(reason)}"
    end
  end

  def start_parent!(app, suffix) when app in [:minimal, :phx_minimal] do
    %{
      image: image,
      network: network,
      parent_name_prefix: parent_prefix
    } = Map.fetch!(@test_apps, app)

    parent_name = "#{parent_prefix}-#{suffix}"
    cleanup!(%{parent_name: parent_name, network: network, app: app})

    :ok = DockerAPI.create_network(network)

    socket = DockerAPI.default_socket_path()

    env =
      [
        "FLAME_NETWORK=#{network}",
        "FLAME_IMAGE=#{image}",
        "RELEASE_COOKIE=#{@integration_cookie}"
      ] ++ parent_env(app)

    {:ok, parent_id} =
      DockerAPI.create_container(%{
        "name" => parent_name,
        "Hostname" => parent_name,
        "Image" => image,
        "Env" => env,
        "Cmd" => [Map.fetch!(@test_apps, app).release_bin, "start"],
        "HostConfig" => %{"Binds" => ["#{socket}:/var/run/docker.sock"]},
        "NetworkingConfig" => %{"EndpointsConfig" => %{network => %{}}}
      })

    :ok = DockerAPI.start_container(parent_id)
    wait_until_running!(parent_id, 30_000)
    wait_until_rpc!(parent_name, Map.fetch!(@test_apps, app).release_bin, 30_000)

    %{parent_name: parent_name, parent_id: parent_id, network: network, app: app}
  end

  def cleanup!(%{parent_name: parent_name, network: network, app: app}) do
    runner_filter = Map.fetch!(@test_apps, app).runner_name_filter

    _ = DockerAPI.stop_and_remove_container(parent_name)
    remove_containers_by_name(runner_filter)
    remove_containers_by_name(parent_name)
    DockerAPI.remove_network(network)
  end

  def wait_for_no_runners!(app, timeout_ms \\ 30_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_no_runners!(app, deadline)
  end

  defp do_wait_for_no_runners!(app, deadline) do
    if runner_containers(app) == [] do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        raise "runner containers still present: #{inspect(runner_containers(app))}"
      end

      Process.sleep(200)
      do_wait_for_no_runners!(app, deadline)
    end
  end

  def runner_containers(app) do
    filter = Map.fetch!(@test_apps, app).runner_name_filter

    case DockerAPI.list_containers(all: true, filters: %{"name" => [filter]}) do
      {:ok, containers} ->
        containers

      {:error, _} ->
        {:ok, containers} = DockerAPI.list_containers(all: true)

        Enum.filter(containers, fn container ->
          container
          |> Map.get("Names", [])
          |> Enum.any?(fn name -> String.contains?(name, filter) end)
        end)
    end
  end

  def exec_rpc!(parent_name, app) do
    %{release_bin: bin, rpc: rpc} = Map.fetch!(@test_apps, app)

    case DockerAPI.exec(parent_name, [bin, "rpc", rpc]) do
      {:ok, output} ->
        output

      {:error, reason} ->
        raise "rpc failed: #{inspect(reason)}"
    end
  end

  defp parent_env(:minimal), do: []

  defp parent_env(:phx_minimal) do
    [
      "PHX_SERVER=true",
      "SECRET_KEY_BASE=yU6FuZbC4EGZtSSR39kyGBPzG5S3XubPjhj+Har5+wsnogPrt+zg4zED8p02qINt"
    ]
  end

  defp wait_until_running!(container_id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    if running?(container_id) do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        raise "container #{container_id} did not start within #{timeout_ms}ms"
      end

      Process.sleep(200)
      wait_until_running!(container_id, timeout_ms)
    end
  end

  defp running?(container_id) do
    case DockerAPI.inspect_container(container_id) do
      {:ok, %{"State" => %{"Running" => true}}} -> true
      _ -> false
    end
  end

  defp wait_until_rpc!(parent_name, release_bin, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    case DockerAPI.exec(parent_name, [release_bin, "rpc", ":ok"]) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        if System.monotonic_time(:millisecond) > deadline do
          raise "release rpc on #{parent_name} not ready within #{timeout_ms}ms"
        end

        Process.sleep(200)
        wait_until_rpc!(parent_name, release_bin, timeout_ms)
    end
  end

  defp remove_containers_by_name(name) do
    case DockerAPI.list_containers(all: true, filters: %{"name" => [name]}) do
      {:ok, containers} ->
        Enum.each(containers, fn %{"Id" => id} -> DockerAPI.stop_and_remove_container(id) end)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end
end
