defmodule Funnel.MixProject do
  use Mix.Project

  def project do
    [
      app: :funnel,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Funnel.Application, []}
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:typed_struct, "~> 0.2.1"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      # TODO(indutny): use to limit concurrency when reaching out to external
      # servers.
      {:poolboy, "~> 1.5.1"},
      # TODO(indutny): use in conjunction with STARTTLS to verify the remote
      # server?
      {:ssl_verify_fun, "~> 1.1"},
      # TODO(indutny): use this for better TCP server performance.
      {:ranch, "~> 2.0"}
    ]
  end
end
