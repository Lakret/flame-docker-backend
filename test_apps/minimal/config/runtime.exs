import Config

if config_env() in [:prod, :dev] do
  config :flame, :backend, FlameDockerBackend
  config :flame, FlameDockerBackend,
    image: System.get_env("FLAME_IMAGE", "minimal:latest"),
    network: System.get_env("FLAME_NETWORK", "minimal_flame_docker_backend_test")
end
