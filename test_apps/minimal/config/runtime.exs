import Config

if config_env() in [:prod, :dev] do
  config :flame, :backend, FLAMEDockerBackend

  config :flame, FLAMEDockerBackend,
    image: System.get_env("FLAME_IMAGE", "minimal:latest"),
    network: System.get_env("FLAME_NETWORK", "minimal_flame_docker_backend_test")
end
