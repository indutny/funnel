defmodule Funnel.Application do
  @moduledoc false

  use Application

  alias Funnel.Server

  @impl true
  def start(_type, _args) do
    port = Application.fetch_env!(:funnel, :port)

    children = [
      {Funnel.Repo, []},
      {Task.Supervisor, name: Funnel.ConnectionSupervisor},
      {Funnel.MailScheduler, name: Funnel.MailScheduler},
      {Server, %Server.Config{port: port}}
    ]

    opts = [strategy: :one_for_one, name: Funnel.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
