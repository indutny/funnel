defmodule Funnel.Application do
  @moduledoc false

  use Application

  alias Funnel.Server
  alias Funnel.MailScheduler

  @impl true
  def start(_type, _args) do
    server_config = %Server.Config{
      local_domain: Application.fetch_env!(:funnel, :smtp_domain),
      port: Application.fetch_env!(:funnel, :port),
      certfile: Application.fetch_env!(:funnel, :certfile),
      dhfile: Application.fetch_env!(:funnel, :dhfile),
      keyfile: Application.fetch_env!(:funnel, :keyfile),
      mail_scheduler: {MailScheduler, MailScheduler}
    }

    children = [
      {Funnel.Repo, []},
      {MailScheduler, name: MailScheduler},
      {Server, server_config}
    ]

    opts = [strategy: :one_for_one, name: Funnel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
