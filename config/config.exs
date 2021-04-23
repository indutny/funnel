import Config

config :funnel, Funnel.Repo, database: "priv/database/funnel.db"

config :funnel,
  ecto_repos: [Funnel.Repo],
  port: 4040,
  smtp_domain: "funnel.example",
  max_mail_size: 30 * 1024 * 1024,
  certfile: "priv/keys/cert.pem",
  keyfile: "priv/keys/key.pem"

if Mix.env() == :test do
  import_config "test.exs"
end
