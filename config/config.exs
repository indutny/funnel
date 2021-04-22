import Config

config :funnel, Funnel.Repo, database: "database/funnel.db"

config :funnel,
  ecto_repos: [Funnel.Repo],
  port: 4040,
  smtp_domain: "funnel.example",
  max_mail_size: 30 * 1024 * 1024

if Mix.env() == :test do
  import_config "test.exs"
end
