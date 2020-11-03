defmodule SMTPServer.Connection do
  @enforce_keys [:local_domain, :max_mail_size]
  defstruct [
    :local_domain,
    :remote_domain,
    :max_mail_size,
    :socket,
    in_handshake: true,
    read_timeout: 5000
  ]

  alias SMTPServer.Connection
  alias SMTPServer.Mail

  @doc """
  Start handshake with remote endpoint.
  """
  @spec serve(SMTPServer.Connection) :: :ok
  def serve(conn) do
    {:ok, {remote_addr, _}} = :inet.sockname(conn.socket)
    {:ok, {:hostent, remote_domain, _, _, _, _}} = :inet.gethostbyaddr(remote_addr)

    respond(conn, "220 #{conn.local_domain}")

    handshake(%Connection{conn | remote_domain: remote_domain})
  end

  defp handshake(conn) do
    line = get_line(conn)

    case SMTPProtocol.parse_handshake(line) do
      {:ok, :extended, _} ->
        respond(conn, "250-#{conn.local_domain} greets #{conn.remote_domain}")
        # TODO(indutny): STARTTLS
        # TODO(indutny): 8BITMIME
        # respond(conn, "250-8BITMIME")
        respond(conn, "250-SIZE #{conn.max_mail_size}")
        respond(conn, "250 SMTPUTF8")
        receive_mail(%Connection{conn | in_handshake: false})

      {:ok, :legacy, _} ->
        false
        respond(conn, "250 OK")
        receive_mail(%Connection{conn | in_handshake: false})

      {:error, msg} ->
        respond(conn, "500 #{msg}")
        handshake(conn)
        exit(:unreachable)
    end
  end

  defp get_line(conn, mode \\ :trim) do
    case :gen_tcp.recv(conn.socket, 0, conn.read_timeout) do
      {:ok, "NOOP\r\n"} ->
        respond(conn, "250 OK")
        get_line(conn)

      # TODO(indutny): consider rate-limiting?
      {:ok, "RSET\r\n"} ->
        respond(conn, "250 OK")

        if conn.in_handshake do
          get_line(conn)
        else
          receive_mail(conn)
          exit(:unreachable)
        end

      {:ok, "QUIT\r\n"} ->
        respond(conn, "221 OK")
        exit(:shutdown)

      {:ok, line} ->
        case mode do
          :trim -> line |> String.replace_trailing("\r\n", "")
          :raw -> line
        end

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  defp respond(conn, line) do
    case :gen_tcp.send(conn.socket, line <> "\r\n") do
      :ok ->
        :ok

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  defp receive_mail(conn) do
    from =
      case get_line(conn) do
        "MAIL FROM:" <> from ->
          from

        "DATA" ->
          respond(conn, "503 Command out of sequence")
          receive_mail(conn)
          exit(:unreachable)

        "RCPT TO:" <> _ ->
          respond(conn, "503 Command out of sequence")
          receive_mail(conn)
          exit(:unreachable)
      end

    {from, params} =
      case SMTPProtocol.parse_mail_and_params(from, :mail) do
        {:ok, from, params} ->
          {from, params}

        {:error, msg} ->
          respond(conn, "553 #{msg}")
          receive_mail(conn)
          exit(:unreachable)
      end

    # TODO(indutny): implement it
    if Map.get(params, :body, :normal) != :normal do
      raise "8BITMIME not implemented yet"
    end

    max_size =
      case Map.get(params, :size, conn.max_mail_size) do
        size when size > conn.max_mail_size ->
          respond(conn, "552 Mail exceeds maximum allowed size")
          receive_mail(conn)
          exit(:unreachable)

        size ->
          size
      end

    # TODO(indutny): check that `from` is in allowlist
    # Should probably receive the mail and keep it for a few days until
    # challenge is solved.
    respond(conn, "250 OK")

    mail = %Mail{from: from, to: [], max_size: max_size}

    receive_mail_recipient(conn, mail)
  end

  defp receive_mail_recipient(conn, mail) do
    case get_line(conn) do
      "RCPT TO:" <> rcpt ->
        {rcpt, _params} =
          case SMTPProtocol.parse_mail_and_params(rcpt, :rcpt) do
            {:ok, rcpt, params} ->
              {rcpt, params}

            {:error, msg} ->
              respond(conn, "553 #{msg}")
              receive_mail_recipient(conn, mail)
              exit(:unreachable)
          end

        respond(conn, "250 OK")

        # TODO(indutny): check that `rcpt` is in allowlist
        # 550 - if no such user
        # should also disallow outgoing email (different domain) unless
        # authorized.
        mail = Mail.add_recipient(mail, rcpt)
        receive_mail_recipient(conn, mail)

      "DATA" ->
        case mail.to do
          [] ->
            respond(conn, "554 No valid recipients")
            receive_mail_recipient(conn, mail)
            exit(:unreachable)

          _non_empty ->
            respond(conn, "354 Start mail input; end with <CRLF>.<CRLF>")
            receive_data(conn, mail)
        end
    end
  end

  defp receive_data(conn, mail) do
    case get_line(conn, :raw) do
      "." ->
        process_mail(conn, mail)

      data ->
        # TODO(indutny): 8BITMIME
        mail = Mail.add_data(mail, data)
        receive_data(conn, mail)
    end
  end

  defp process_mail(conn, mail) do
    if Mail.data_size(mail) > mail.max_size do
      respond(conn, "552 Mail exceeds maximum allowed size")
      receive_mail(conn)
      exit(:unreachable)
    end

    IO.inspect(mail)
  end
end
