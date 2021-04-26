defmodule Funnel.Application do
  @moduledoc false

  use Application

  alias Funnel.Challenge
  alias Funnel.MailScheduler
  alias Funnel.Server

  @impl true
  def start(_type, _args) do
    server_config = %Server.Config{
      local_domain: Application.fetch_env!(:funnel, :smtp_domain),
      challenge_url: Application.fetch_env!(:funnel, :challenge_url),
      port: Application.fetch_env!(:funnel, :port),
      certfile: Application.fetch_env!(:funnel, :certfile),
      dhfile: Application.fetch_env!(:funnel, :dhfile),
      keyfile: Application.fetch_env!(:funnel, :keyfile),
      mail_scheduler: {MailScheduler, MailScheduler}
    }

    http_port = Application.fetch_env!(:funnel, :http_port)

    challenge_opts = %Challenge.Options{
      hcaptcha_secret: Application.fetch_env!(:funnel, :hcaptcha_secret),
      hcaptcha_sitekey: Application.fetch_env!(:funnel, :hcaptcha_sitekey)
    }

    children = [
      {Funnel.Repo, []},
      {MailScheduler, name: MailScheduler},
      {Plug.Cowboy, scheme: :http, plug: {Challenge, challenge_opts}, options: [port: http_port]},
      {Server, server_config}
    ]

    opts = [strategy: :one_for_one, name: Funnel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
