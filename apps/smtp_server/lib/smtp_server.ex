defmodule SMTPServer do
  require Logger
  use Task, restart: :permanent

  alias SMTPServer.Connection

  @moduledoc """
  `SMTPServer` implementation.
  """

  def start_link(config, _opts \\ []) do
    {:ok, pid} = Task.start_link(SMTPServer, :listen, [self(), config])

    receive do
      {:port, port} ->
        {:ok, pid, %{port: port}}
    end
  end

  def listen(parent, config) do
    config =
      Map.merge(
        %{
          local_domain: "funnel.localhost",
          max_mail_size: 30 * 1024 * 1024,
          # 5 minutes
          read_timeout: 5 * 60 * 1000,
          port: 0,
          max_line_size: 1024
        },
        config
      )

    {:ok, socket} =
      :gen_tcp.listen(config.port, [
        :binary,
        packet: :line,
        packet_size: config.max_line_size,
        reuseaddr: true,
        active: false
      ])

    {:ok, {addr, actual_port}} = :inet.sockname(socket)

    Logger.info(
      "Accepting connections on " <>
        "#{:inet.ntoa(addr)}:#{actual_port}"
    )

    send(parent, {:port, actual_port})

    accept(config, socket)
  end

  defp accept(config, socket) do
    # TODO(indutny): rate-limiting
    {:ok, remote} = :gen_tcp.accept(socket)

    {:ok, pid} =
      Task.Supervisor.start_child(
        SMTPServer.ConnectionSupervisor,
        fn ->
          remote =
            receive do
              {:socket, socket} -> socket
            end

          start_connection(config, remote)
        end
      )

    :ok = :gen_tcp.controlling_process(remote, pid)
    send(pid, {:socket, remote})

    # Loop
    accept(config, socket)
  end

  defp start_connection(config, remote) do
    {:ok, {remote_addr, _}} = :inet.peername(remote)
    {:ok, remote_host} = :inet.gethostbyaddr(remote_addr)
    {:hostent, remote_domain, _, _, _, _} = remote_host

    {:ok, conn} =
      Connection.start_link(%Connection.Config{
        local_domain: config.local_domain,
        remote_domain: remote_domain,
        max_mail_size: config.max_mail_size
      })

    send_response(remote, Connection.handshake(conn))

    serve(config, remote, conn)
  end

  defp serve(config, remote, conn) do
    case :gen_tcp.recv(remote, 0, config.read_timeout) do
      {:ok, line} ->
        response = Connection.respond_to(conn, line)

        send_response(remote, response)
        serve(config, remote, conn)

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  defp send_response(_, :no_response) do
    # no-op
  end

  defp send_response(remote, {mode, code, line}) when is_bitstring(line) do
    send_response(remote, :last, {mode, code, line})
  end

  defp send_response(remote, {mode, code, [line]}) do
    send_response(remote, :last, {mode, code, line})
  end

  defp send_response(remote, {mode, code, [line | rest]}) do
    send_response(remote, :not_last, {mode, code, line})
    send_response(remote, {mode, code, rest})
  end

  defp send_response(remote, order, {mode, code, line}) do
    response =
      case order do
        :not_last -> "#{code}-#{line}\r\n"
        :last -> "#{code} #{line}\r\n"
      end

    case :gen_tcp.send(remote, response) do
      :ok -> :ok
      {:error, :closed} -> exit(:shutdown)
    end

    if order == :last and mode == :shutdown do
      :ok = :gen_tcp.shutdown(remote, :write)
    end
  end
end
