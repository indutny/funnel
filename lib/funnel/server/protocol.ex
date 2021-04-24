defmodule Funnel.Server.Protocol do
  use Task
  use TypedStruct

  @behaviour :ranch_protocol

  @typep transport() :: module()

  require Logger

  typedstruct module: Config do
    field :transport, module()
    field :remote, :ranch_transport.socket()

    field :local_domain, String.t(), enforce: true
    field :max_mail_size, non_neg_integer(), enforce: true
    field :read_timeout, timeout(), enforce: true

    field :max_buffer_size, non_neg_integer(), default: 1024

    field :ssl_opts, :ranch_ssl.opts(), enforce: true
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
    {:ok, {local_ip, _}} = transport.sockname(remote)
    {:ok, remote_host} = :inet.gethostbyaddr(remote_ip)
    {:hostent, remote_domain, _, _, _, _} = remote_host

    {:ok, conn} =
      SMTPServer.start_link(%SMTPServer.Config{
        local_domain: config.local_domain,
        local_addr: List.to_string(:inet.ntoa(local_ip)),
        remote_domain: List.to_string(remote_domain),
        remote_addr: List.to_string(:inet.ntoa(remote_ip)),
        max_mail_size: config.max_mail_size,
        mail_scheduler: {Funnel.MailScheduler, Funnel.MailScheduler}
      })

    config = %Config{config | transport: transport, remote: remote}
    send_response(config, SMTPServer.handshake(conn))

    serve(config, conn, <<>>)
  end

  @spec serve(Config.t(), SMTPServer.t(), String.t()) :: nil
  def serve(config, conn, buffer) do
    case config.transport.recv(config.remote, 0, config.read_timeout) do
      {:ok, packet} ->
        {config, buffer} = read_line(config, conn, buffer <> packet)

        if byte_size(buffer) > config.max_buffer_size do
          send_response(config, {:shutdown, 500, "Line too long"})
          exit(:shutdown)
        end

        serve(config, conn, buffer)

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  @spec read_line(Config.t(), SMTPServer.t(), String.t()) :: {Config.t(), String.t()}
  def read_line(config, conn, buffer) do
    case String.split(buffer, ~r/(?<=\r\n|\n)/, parts: 2) do
      [line, buffer] ->
        response = SMTPServer.respond_to(conn, line)
        config = send_response(config, response)

        read_line(config, conn, buffer)

      [buffer] ->
        {config, buffer}
    end
  end

  @spec send_response(Config.t(), SMTPServer.response()) :: Config.t()
  defp send_response(_config, :no_response) do
    # no-op
  end

  defp send_response(config, {mode, code, line}) when is_bitstring(line) do
    send_response(config, :last, {mode, code, line})
  end

  defp send_response(config, {mode, code, [line]}) do
    send_response(config, :last, {mode, code, line})
  end

  defp send_response(config, {mode, code, [line | rest]}) do
    config = send_response(config, :not_last, {mode, code, line})
    send_response(config, {mode, code, rest})
  end

  @spec send_response(
          Config.t(),
          :not_last | :last,
          SMTPServer.response()
        ) :: Config.t()
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

    case mode do
      :shutdown when order == :last ->
        :ok = config.transport.shutdown(config.remote, :write)
        config

      :starttls when config.transport == :ranch_tcp ->
        {:ok, secure} = :ranch_ssl.handshake(config.remote, config.ssl_opts, config.read_timeout)
        %Config{config | transport: :ranch_ssl, remote: secure}

      _ ->
        config
    end
  end
end
