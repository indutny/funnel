import Config

config :funnel, Funnel.Repo, database: "priv/database/funnel.db"

config :funnel,
  ecto_repos: [Funnel.Repo],
  port: 4040,
  smtp_domain: "funnel.example",
  max_mail_size: 30 * 1024 * 1024,
  certfile: "priv/keys/cert.pem",
  dhfile: "priv/keys/dh.pem",
  keyfile: "priv/keys/key.pem"

case Mix.env() do
  :test ->
    import_config "test.exs"

  :prod ->
    import_config "prod.exs"

  _ ->
    :ok
end
