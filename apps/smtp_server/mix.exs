defmodule SMTPServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :smtp_server,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SMTPServer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:smtp_protocol, in_umbrella: true},
      {:typed_struct, "~> 0.2.1"},
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
