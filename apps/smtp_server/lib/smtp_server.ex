defmodule SMTPServer do
  require Logger

  @moduledoc """
  Documentation for `SMTPServer`.
  """

  def listen(port \\ 0, opts \\ []) do
    {:ok, socket} = :gen_tcp.listen(port, [
      :binary,
      packet: :line,
      packet_size: Keyword.get(opts, :max_line_size, 1024),
      reuseaddr: true,
      active: false,
    ])

    {:ok, {addr, actual_port}} = :inet.sockname(socket)

    Logger.info("Accepting connections on " <>
      "#{:inet.ntoa addr}:#{actual_port}")

    case Keyword.fetch(opts, :port_listener) do
      {:ok, pid} ->
        send(pid, {:port, actual_port})
      _ -> nil
    end

    accept(socket)
  end

  defp accept(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(SMTPServer.ConnectionSupervisor,
      fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)

    accept(socket)
  end

  defp recv(socket) do
    # TODO(indutny): configurable timeout
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, line} -> String.split(line)
      {:error, :closed} -> exit(:shutdown)
    end
  end

  defp respond(socket, line) do
    :ok = :gen_tcp.send(socket, line <> "\r\n")
  end

  defp serve(socket) do
    # TODO(indutny): probably slow?
    domain = Application.fetch_env!(:smtp_server, :smtp_domain)
    max_mail_size = Application.fetch_env!(:smtp_server, :max_mail_size)

    {:ok, {remote_addr, _}} = :inet.sockname(socket)
    {:ok, {:hostent, client_domain, _, _, _, _}} =
      :inet.gethostbyaddr(remote_addr)

    respond(socket, "220 #{domain}")

    is_extended = case recv(socket) do
      ["HELO", domain] -> false
      ["EHLO", domain] -> true
      ["EHLO"] -> true
    end

    if is_extended do
      respond(socket, "250-#{domain} greets #{client_domain}")
      # TODO(indutny): STARTTLS
      respond(socket, "250-8BITMIME")
      respond(socket, "250-SIZE #{max_mail_size}")
      respond(socket, "250 SMTPUTF8")
    else
      respond(socket, "250 OK")
    end

    receive_mail(socket)
  end

  defp receive_mail(socket) do
  end
end
