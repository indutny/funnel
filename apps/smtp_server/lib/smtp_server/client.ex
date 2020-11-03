defmodule SMTPServer.Client do
  @enforce_keys [:local_domain, :max_mail_size]
  defstruct [:local_domain, :max_mail_size, :socket, in_handshake: true, read_timeout: 5000]

  alias SMTPServer.Client
  alias SMTPServer.Mail

  @doc """
  Start handshake with remote endpoint.
  """
  @spec start(SMTPServer.Client) :: :ok
  def start(client) do
    {:ok, {remote_addr, _}} = :inet.sockname(client.socket)
    {:ok, {:hostent, remote_domain, _, _, _, _}} = :inet.gethostbyaddr(remote_addr)

    respond(client, "220 #{client.local_domain}")

    handshake = get_line(client)

    is_extended =
      case SMTPProtocol.parse_handshake(handshake) do
        {:ok, :extended, _} -> true
        {:ok, :legacy, _} -> false
        {:error, msg} -> fail(client, 500, msg)
      end

    if is_extended do
      respond(client, "250-#{client.local_domain} greets #{remote_domain}")
      # TODO(indutny): STARTTLS
      respond(client, "250-8BITMIME")
      respond(client, "250-SIZE #{client.max_mail_size}")
      respond(client, "250 SMTPUTF8")
    else
      respond(client, "250 OK")
    end

    receive_mail(%Client{client | in_handshake: false})
  end

  defp get_line(client) do
    case :gen_tcp.recv(client.socket, 0, client.read_timeout) do
      {:ok, "NOOP\r\n"} ->
        respond(client, "250 OK")
        get_line(client)

      # TODO(indutny): consider rate-limiting?
      {:ok, "RSET\r\n"} ->
        respond(client, "250 OK")

        if client.in_handshake do
          get_line(client)
        else
          receive_mail(client)
          exit(:unreachable)
        end

      {:ok, "QUIT\r\n"} ->
        respond(client, "221 OK")
        exit(:shutdown)

      {:ok, line} ->
        line
        |> String.replace_trailing("\r\n", "")

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  defp respond(client, line) do
    case :gen_tcp.send(client.socket, line <> "\r\n") do
      :ok ->
        :ok

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  defp fail(client, code, line) do
    respond(client, "#{code} #{line}")
    :gen_tcp.shutdown(client.socket, :write)
    exit(:shutdown)
  end

  defp receive_mail(client) do
    "MAIL FROM:" <> from = get_line(client)

    {from, params} =
      case SMTPProtocol.parse_mail_and_params(from, :from) do
        {:ok, from, params} -> {from, params}
        {:error, msg} -> fail(client, 553, msg)
      end

    case Map.get(params, :size) do
      size when size > client.max_mail_size ->
        fail(client, 552, "Mail exceeds maximum allowed size")

      _ ->
        :ok
    end

    # TODO(indutny): check that `from` is in allowlist
    # Should probably receive the mail and keep it for a few days until
    # challenge is solved.
    respond(client, "250 OK")

    mail = %Mail{from: from, to: []}

    recv_mail_recipient(client, mail)
  end

  defp recv_mail_recipient(client, mail) do
    case get_line(client) do
      "RCPT TO:" <> rcpt ->
        {rcpt, params} =
          case SMTPProtocol.parse_mail_and_params(rcpt, :rcpt) do
            {:ok, rcpt, params} -> {rcpt, params}
            {:error, msg} -> fail(client, 553, msg)
          end

        respond(client, "250 OK")

        # TODO(indutny): check that `rcpt` is in allowlist
        # 550 - if no such user
        # should also disallow outgoing email (different domain) unless
        # authorized.
        mail = Mail.add_recipient(mail, rcpt)
        recv_mail_recipient(client, mail)

      "DATA" ->
        respond(client, "354  Start mail input; end with <CRLF>.<CRLF>")
        exit(:not_implemented)
    end
  end
end
