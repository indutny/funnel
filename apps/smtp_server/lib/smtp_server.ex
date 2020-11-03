defmodule SMTPServer do
  require Logger

  @moduledoc """
  `SMTPServer` implementation.
  """

  @enforce_keys [:domain, :max_mail_size]
  defstruct [:domain, :max_mail_size, read_timeout: 5000]

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

    config = %SMTPServer{
      domain: Application.fetch_env!(:smtp_server, :smtp_domain),
      max_mail_size: Application.fetch_env!(:smtp_server, :max_mail_size)
    }

    accept(config, socket)
  end

  defp accept(config, socket) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, pid} =
      Task.Supervisor.start_child(
        SMTPServer.ConnectionSupervisor,
        fn ->
          receive do
            :ready -> :ok
          end

          handshake(config, client)
        end
      )

    :ok = :gen_tcp.controlling_process(client, pid)
    send(pid, :ready)

    accept(config, socket)
  end

  defp get_line(config, socket) do
    case :gen_tcp.recv(socket, 0, config.read_timeout) do
      {:ok, line} -> String.split(line)
      {:error, :closed} -> exit(:shutdown)
    end
  end

  defp respond(socket, line) do
    :ok = :gen_tcp.send(socket, line <> "\r\n")
  end

  defp handshake(config, socket) do
    {:ok, {remote_addr, _}} = :inet.sockname(socket)
    {:ok, {:hostent, remote_domain, _, _, _, _}} = :inet.gethostbyaddr(remote_addr)

    respond(socket, "220 #{config.domain}")

    is_extended =
      case get_line(config, socket) do
        ["HELO", _] -> false
        ["EHLO", _] -> true
        ["EHLO"] -> true
      end

    if is_extended do
      respond(socket, "250-#{config.domain} greets #{remote_domain}")
      # TODO(indutny): STARTTLS
      respond(socket, "250-8BITMIME")
      respond(socket, "250-SIZE #{config.max_mail_size}")
      respond(socket, "250 SMTPUTF8")
    else
      respond(socket, "250 OK")
    end

    receive_mail(config, socket)
  end

  defp receive_mail(config, socket) do
    ["MAIL", "FROM:" <> path | _params] = get_line(config, socket)

    mailbox =
      case SMTPProtocol.parse_path(path) do
        {:ok, mailbox} ->
          mailbox

        {:error, msg} ->
          respond(socket, "553 " <> msg)
          exit(:shutdown)
      end

    respond(socket, "250 OK")
  end
end
