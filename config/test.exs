use Mix.Config

config :funnel, Funnel.Repo,
  database: "database/funnel_test.db",
  pool: Ecto.Adapters.SQL.Sandbox
