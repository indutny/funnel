defmodule Funnel.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      # TODO(indutny): use to limit concurrency when reaching out to external
      # servers.
      {:poolboy, "~> 1.5.1"},
    ]
  end
end
