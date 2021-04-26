import Config

config :funnel, Funnel.Repo, database: "priv/database/funnel.db"

config :funnel,
  ecto_repos: [Funnel.Repo],
  port: 4040,
  http_port: 8080,
  smtp_domain: "funnel.example",
  challenge_url: "https://funnel.example/",
  max_mail_size: 30 * 1024 * 1024,
  certfile: "priv/keys/cert.pem",
  dhfile: "priv/keys/dh.pem",
  keyfile: "priv/keys/key.pem",
  hcaptcha_secret: "0x0000000000000000000000000000000000000000",
  hcaptcha_sitekey: "10000000-ffff-ffff-ffff-000000000001"

case Mix.env() do
  :test ->
    import_config "test.exs"

  :prod ->
    import_config "prod.exs"

  _ ->
    :ok
end
