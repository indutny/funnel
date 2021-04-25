defmodule Funnel.MixProject do
  use Mix.Project

  def project do
    [
      app: :funnel,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Funnel.Application, []}
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:typed_struct, "~> 0.2.1"},
      {:ecto_sql, "~> 3.6"},
      {:ecto_sqlite3, "~> 0.5.5"},
      # TODO(indutny): use to limit concurrency when reaching out to external
      # servers.
      {:poolboy, "~> 1.5"},
      {:ssl_verify_fun, "~> 1.1"},
      # TODO(indutny): use this for better TCP server performance.
      {:ranch, "~> 1.7"},
      {:certifi, "~> 2.6"},
      {:plug_cowboy, "~> 2.5"},
      {:jason, "~> 1.2"},
      {:hackney, "~> 1.17"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
