defmodule Minimal.MixProject do
  use Mix.Project

  def project do
    [
      app: :minimal,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Minimal.Application, []}
    ]
  end

  defp deps do
    [
      {:flame, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:flame_docker_backend, path: "../../"}
    ]
  end
end
