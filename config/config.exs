import Config

config :funnel, Funnel.Repo,
  database: "funnel_repo",
  hostname: "localhost"

config :funnel,
  ecto_repos: [Funnel.Repo],
  port: 4040,
  smtp_domain: "funnel.example",
  max_mail_size: 30 * 1024 * 1024
