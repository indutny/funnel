defmodule Funnel.Application do
  @moduledoc false

  use Application

  alias Funnel.Server

  @impl true
  def start(_type, _args) do
    port = Application.fetch_env!(:funnel, :port)
    certfile = Application.fetch_env!(:funnel, :certfile)
    keyfile = Application.fetch_env!(:funnel, :keyfile)

    children = [
      {Funnel.Repo, []},
      {Task.Supervisor, name: Funnel.ConnectionSupervisor},
      {Funnel.MailScheduler, name: Funnel.MailScheduler},
      {Funnel.ClientPool, name: Funnel.ClientPool},
      {Server, %Server.Config{port: port, certfile: certfile, keyfile: keyfile}}
    ]

    opts = [strategy: :one_for_one, name: Funnel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
