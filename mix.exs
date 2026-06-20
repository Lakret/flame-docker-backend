defmodule FLAMEDockerBackend.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Lakret/flame-docker-backend"

  def project do
    [
      app: :flame_docker_backend,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
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
      maintainers: ["Lakret"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        {"docs/guides/flame_backends.md", title: "Building FLAME Backends"}
      ]
    ]
  end

  defp aliases do
    [
      test: ["test --exclude docker"],
      "test.docker": ["test --only docker"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
