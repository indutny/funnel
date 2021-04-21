use Mix.Config

config :funnel, Funnel.Repo,
  database: "database/funnel_test.db",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
