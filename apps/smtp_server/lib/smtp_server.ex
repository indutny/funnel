defmodule SMTPServer do
  require Logger

  alias SMTPServer.Client

  @moduledoc """
  `SMTPServer` implementation.
  """
  @spec listen(integer, keyword()) :: :ok
  def listen(port \\ 0, opts \\ []) do
    {:ok, socket} =
      :gen_tcp.listen(port, [
        :binary,
        packet: :line,
        packet_size: Keyword.get(opts, :max_line_size, 1024),
        reuseaddr: true,
        active: false
      ])

    {:ok, {addr, actual_port}} = :inet.sockname(socket)

    Logger.info(
      "Accepting connections on " <>
        "#{:inet.ntoa(addr)}:#{actual_port}"
    )

    case Keyword.fetch(opts, :port_listener) do
      {:ok, pid} ->
        send(pid, {:port, actual_port})

      _ ->
        :ok
    end

    client_template = %Client{
      local_domain: Application.fetch_env!(:smtp_server, :smtp_domain),
      max_mail_size: Application.fetch_env!(:smtp_server, :max_mail_size)
    }

    accept(socket, client_template)
  end

  defp accept(socket, client_template) do
    {:ok, remote} = :gen_tcp.accept(socket)

    {:ok, pid} =
      Task.Supervisor.start_child(
        SMTPServer.ConnectionSupervisor,
        fn ->
          receive do
            :ready -> :ok
          end

          Client.start(%Client{client_template | socket: remote})
        end
      )

    :ok = :gen_tcp.controlling_process(remote, pid)
    send(pid, :ready)

    accept(socket, client_template)
  end
end
