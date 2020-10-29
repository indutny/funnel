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

    respond(socket, "220 #{domain}")

    {is_extended, client_domain} = case recv(socket) do
      ["HELO", domain] -> {false, domain}
      ["EHLO"] -> {true, nil}
      ["EHLO", domain] -> {true, domain}
    end

    if is_extended do
      respond(socket, "250-#{domain} greets " <>
        "#{client_domain || "mysterious client"}")
    end
    respond(socket, "250 ok")

    :gen_tcp.close(socket)
  end
end
