defmodule Funnel.Server.Protocol do
  use Task
  use TypedStruct

  @type transport() :: module()

  require Logger

  typedstruct module: Config do
    field :transport, module()
    field :remote, :ranch_transport.socket()

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

    config = %Config{config| transport: transport, remote: remote}
    send_response(config, SMTPServer.handshake(conn))

    serve(config, conn, <<>>)
  end

  @spec serve(Config.t(), SMTPServer.t(), binary()) :: nil
  def serve(config, conn, buffer) do
    case config.transport.recv(config.remote, 0, config.read_timeout) do
      {:ok, packet} ->
        buffer = buffer <> packet
        buffer = read_line(config, conn, buffer)
        serve(config, conn, buffer)

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  @spec read_line(Config.t(), SMTPServer.t(), binary()) :: binary()
  def read_line(config, conn, buffer) do
    case String.split(buffer, ~r/(?<=\r\n|\n)/, parts: 2) do
      [line, buffer] ->
        response = SMTPServer.respond_to(conn, line)
        send_response(config, response)

        read_line(config, conn, buffer)

      [buffer] ->
        buffer
    end
  end

  @spec send_response(Config.t(), SMTPServer.response()) :: nil
  defp send_response(_, :no_response) do
    # no-op
  end

  defp send_response(config, {mode, code, line}) when is_bitstring(line) do
    send_response(config, :last, {mode, code, line})
  end

  defp send_response(config, {mode, code, [line]}) do
    send_response(config, :last, {mode, code, line})
  end

  defp send_response(config, {mode, code, [line | rest]}) do
    send_response(config, :not_last, {mode, code, line})
    send_response(config, {mode, code, rest})
  end

  @spec send_response(
    Config.t(),
          :not_last | :last,
          SMTPServer.response()
        ) :: nil
  defp send_response(config, order, {mode, code, line}) do
    response =
      case order do
        :not_last -> "#{code}-#{line}\r\n"
        :last -> "#{code} #{line}\r\n"
      end

    case config.transport.send(config.remote, response) do
      :ok -> :ok
      {:error, :closed} -> exit(:shutdown)
    end

    if order == :last and mode == :shutdown do
      :ok = config.transport.shutdown(config.remote, :write)
    end
  end
end
