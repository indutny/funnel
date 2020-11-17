use Mix.Config

config :funnel, MyApp.Repo,
  database: "funnel_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
