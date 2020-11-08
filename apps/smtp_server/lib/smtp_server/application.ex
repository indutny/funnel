defmodule SMTPServer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.fetch_env!(:smtp_server, :port)

    children = [
      {Task.Supervisor, name: SMTPServer.ConnectionSupervisor},
      {SMTPServer, %{port: port}}
    ]

    opts = [strategy: :one_for_one, name: SMTPServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
