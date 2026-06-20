import Config

if config_env() in [:prod, :dev] do
  flame_opts = [
    image: System.get_env("FLAME_IMAGE", "minimal:latest"),
    network: System.get_env("FLAME_NETWORK", "minimal_flame_docker_backend_test")
  ]

  flame_opts =
    case System.get_env("FLAME_HOST_CONFIG") do
      nil -> flame_opts
      json -> Keyword.put(flame_opts, :host_config, Jason.decode!(json))
    end

  config :flame, :backend, FLAMEDockerBackend
  config :flame, FLAMEDockerBackend, flame_opts
end
