defmodule FlameDockerBackend.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Lakret/flame-docker-backend"

  def project do
    [
      app: :flame_docker_backend,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "FLAME backend that provisions runners as Docker containers via the Docker Engine API",
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets]
    ]
  end

  defp deps do
    [
      {:flame, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp aliases do
    [
      test: ["test --exclude docker"]
    ]
  end
end
