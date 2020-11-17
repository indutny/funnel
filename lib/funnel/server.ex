defmodule Funnel.Server do
  use Task, restart: :permanent
  use TypedStruct

  require Logger

  typedstruct module: Config do
    field :local_domain, :inet.hostname(), default: "funnel.localhost"
    field :max_mail_size, non_neg_integer(), default: 30 * 1024 * 1024
    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000
    field :port, non_neg_integer(), default: 0

    # TODO(indutny): line size limit leads to unrecoverable :emsgsize error.
    # Needs to be able to send the 500 response without closing the socket.
    field :max_line_size, non_neg_integer(), default: 512
  end

  alias FunnelSMTP.Server, as: Connection

  @moduledoc """
  Server implementation.
  """

  @spec start_link(Config.t(), [term()]) :: {:ok, pid(), map()}
  def start_link(config, _opts \\ []) do
    {:ok, pid} = Task.start_link(Funnel.Server, :listen, [self(), config])

    receive do
      {:port, port} ->
        {:ok, pid, %{port: port}}
    end
  end

  @spec listen(pid(), Config.t()) :: nil
  def listen(parent, config) do
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

  @spec listen(Config.t(), :inet.socket()) :: nil
  defp accept(config, socket) do
    # TODO(indutny): rate-limiting
    {:ok, remote} = :gen_tcp.accept(socket)

    {:ok, pid} =
      Task.Supervisor.start_child(
        Funnel.ConnectionSupervisor,
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

  @spec start_connection(Config.t(), :inet.socket()) :: nil
  defp start_connection(config, remote) do
    {:ok, {remote_addr, _}} = :inet.peername(remote)
    {:ok, remote_host} = :inet.gethostbyaddr(remote_addr)
    {:hostent, remote_domain, _, _, _, _} = remote_host

    {:ok, conn} =
      Connection.start_link(%Connection.Config{
        local_domain: config.local_domain,
        remote_domain: remote_domain,
        max_mail_size: config.max_mail_size,
        mail_scheduler: {Funnel.MailScheduler, Funnel.MailScheduler}
      })

    send_response(remote, Connection.handshake(conn))

    serve(config, remote, conn)
  end

  @spec serve(Config.t(), :inet.socket(), Connection.t()) :: nil
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

  @spec send_response(:inet.socket(), Connection.response()) :: nil
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

  @spec send_response(
          :inet.socket(),
          :not_last | :last,
          Connection.response()
        ) :: nil
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
