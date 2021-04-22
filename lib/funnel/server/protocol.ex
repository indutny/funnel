defmodule Funnel.Server.Protocol do
  use Task
  use TypedStruct

  @type socket() :: :ranch_transport.socket()
  @type transport() :: module()

  require Logger

  typedstruct module: Config do
    field :local_domain, String.t(), default: "funnel.localhost"
    field :max_mail_size, non_neg_integer(), default: 30 * 1024 * 1024
    # 5 minutes
    field :read_timeout, timeout(), default: 5 * 60 * 1000

    # TODO(indutny): line size limit leads to unrecoverable :emsgsize error.
    # Needs to be able to send the 500 response without closing the socket.
    field :max_line_size, non_neg_integer(), default: 512
  end

  alias FunnelSMTP.Server, as: SMTPServer

  @spec start_link(reference(), transport(), Config.t()) :: {:ok, pid()}
  def start_link(ref, transport, config) do
    Task.start_link(Funnel.Server.Protocol, :accept, [ref, transport, config])
  end

  @spec accept(reference(), transport(), Config.t()) :: nil
  def accept(ref, transport, config) do
    # TODO(indutny): rate-limiting
    {:ok, remote} = :ranch.handshake(ref)

    {:ok, {remote_ip, _}} = transport.peername(remote)
    {:ok, remote_host} = :inet.gethostbyaddr(remote_ip)
    {:hostent, remote_domain, _, _, _, _} = remote_host

    {:ok, conn} =
      SMTPServer.start_link(%SMTPServer.Config{
        local_domain: config.local_domain,
        remote_domain: List.to_string(remote_domain),
        max_mail_size: config.max_mail_size,
        mail_scheduler: {Funnel.MailScheduler, Funnel.MailScheduler}
      })

    send_response(remote, transport, SMTPServer.handshake(conn))

    serve(remote, transport, conn, config)
  end

  @spec serve(socket(), transport(), SMTPServer.t(), Config.t()) :: nil
  def serve(remote, transport, conn, config) do
    case transport.recv(remote, 0, config.read_timeout) do
      {:ok, packet} ->
        IO.puts(packet)
        line = "ohai"
        response = SMTPServer.respond_to(conn, line)

        send_response(remote, transport, response)
        serve(remote, transport, conn, config)

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  @spec send_response(socket(), transport(), SMTPServer.response()) :: nil
  defp send_response(_, _, :no_response) do
    # no-op
  end

  defp send_response(remote, transport, {mode, code, line}) when is_bitstring(line) do
    send_response(remote, transport, :last, {mode, code, line})
  end

  defp send_response(remote, transport, {mode, code, [line]}) do
    send_response(remote, transport, :last, {mode, code, line})
  end

  defp send_response(remote, transport, {mode, code, [line | rest]}) do
    send_response(remote, transport, :not_last, {mode, code, line})
    send_response(remote, transport, {mode, code, rest})
  end

  @spec send_response(
          socket(),
          transport(),
          :not_last | :last,
          SMTPServer.response()
        ) :: nil
  defp send_response(remote, transport, order, {mode, code, line}) do
    response =
      case order do
        :not_last -> "#{code}-#{line}\r\n"
        :last -> "#{code} #{line}\r\n"
      end

    case transport.send(remote, response) do
      :ok -> :ok
      {:error, :closed} -> exit(:shutdown)
    end

    if order == :last and mode == :shutdown do
      :ok = transport.shutdown(remote, :write)
    end
  end
end
