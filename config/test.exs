use Mix.Config

config :funnel, Funnel.Repo,
  database: "priv/database/funnel_test.db",
  pool: Ecto.Adapters.SQL.Sandbox
