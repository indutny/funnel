use Mix.Config

config :funnel, Funnel.Repo,
  database: "funnel_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
