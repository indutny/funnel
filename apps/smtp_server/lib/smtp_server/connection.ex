defmodule SMTPServer.Connection do
  alias SMTPServer.Connection
  alias SMTPServer.Mail

  @enforce_keys [:local_domain, :max_mail_size]
  defstruct [
    :local_domain,
    :remote_domain,
    :max_mail_size,
    :socket,
    read_timeout: 5000
  ]

  @type state() :: :handshake | :main | {:rcpt, Mail} | {:data, Mail}

  @type handle_return ::
          {:no_response, state()}
          | {:response, state(), integer, String.t()}

  @doc """
  Start handshake with remote endpoint.
  """
  @spec serve(%Connection{}) :: :ok
  def serve(conn) do
    {:ok, {remote_addr, _}} = :inet.sockname(conn.socket)
    {:ok, {:hostent, remote_domain, _, _, _, _}} = :inet.gethostbyaddr(remote_addr)

    respond(conn, "220 #{conn.local_domain}")

    loop(:handshake, %Connection{conn | remote_domain: remote_domain})
  end

  defp loop(state, conn) do
    line = get_line(conn, state)

    case handle_line(conn, state, line) do
      {:no_response, new_state} ->
        loop(new_state, conn)

      {:response, new_state, code, msg} ->
        respond(conn, "#{code} #{msg}")
        loop(new_state, conn)
    end
  end

  @spec handle_line(%Connection{}, state(), String.t()) :: handle_return
  defp handle_line(conn, state, line)

  defp handle_line(_, :handshake, "RSET") do
    {:response, :handshake, 250, "OK"}
  end

  defp handle_line(_, _, "RSET") do
    {:response, :main, 250, "OK"}
  end

  defp handle_line(_, state, "NOOP") do
    {:response, state, 250, "OK"}
  end

  defp handle_line(conn, _, "QUIT") do
    respond(conn, "221 OK")
    :gen_tcp.shutdown(conn.socket, :write)
    exit(:shutdown)
  end

  defp handle_line(conn, :handshake, line) do
    case SMTPProtocol.parse_handshake(line) do
      {:ok, :extended, _} ->
        respond(conn, "250-#{conn.local_domain} greets #{conn.remote_domain}")
        # TODO(indutny): STARTTLS
        # TODO(indutny): 8BITMIME
        # respond(conn, "250-8BITMIME")
        respond(conn, "250-SIZE #{conn.max_mail_size}")
        {:response, :main, 250, "SMTPUTF8"}

      {:ok, :legacy, _} ->
        {:response, :main, 250, "OK"}

      {:error, msg} ->
        {:response, :handshake, 500, msg}
    end
  end

  defp handle_line(_, :main, "VRFY" <> _) do
    # Not really supported
    {:response, :main, 252, "I will be happy to accept your message"}
  end

  defp handle_line(conn, :main, "MAIL FROM:" <> from) do
    case SMTPProtocol.parse_mail_and_params(from, :mail) do
      {:ok, from, params} ->
        case receive_mail(conn, from, params) do
          {:ok, mail} ->
            {:response, {:rcpt, mail}, 250, "OK"}

          {:error, :max_size_exceeded} ->
            {:response, :main, 552, "Mail exceeds maximum allowed size"}
        end

      {:error, msg} ->
        {:response, :main, 553, msg}
    end
  end

  defp handle_line(conn, {:rcpt, mail}, "RCPT TO:" <> rcpt) do
    case SMTPProtocol.parse_mail_and_params(rcpt, :rcpt) do
      {:ok, rcpt, params} ->
        case receive_rcpt(conn, mail, rcpt, params) do
          {:ok, new_mail} -> {:response, {:rcpt, new_mail}, 250, "OK"}
        end

      {:error, msg} ->
        {:response, {:rcpt, mail}, 553, msg}
    end
  end

  defp handle_line(_, {:rcpt, mail}, "DATA") do
    case mail.to do
      [] ->
        {:response, {:rcpt, mail}, 554, "No valid recipients"}

      _non_empty ->
        {:response, {:data, mail}, 354, "Start mail input; end with <CRLF>.<CRLF>"}
    end
  end

  defp handle_line(_, {:data, mail}, ".\r\n") do
    if Mail.data_size(mail) > mail.max_size do
      {:response, :main, 552, "Mail exceeds maximum allowed size"}
    else
      process_mail(mail)
      {:response, :main, 250, "OK"}
    end
  end

  defp handle_line(_, {:data, mail}, data) do
    # TODO(indutny): 8BITMIME
    {:no_response, {:data, Mail.add_data(mail, data)}}
  end

  defp handle_line(_, state, "DATA") do
    {:response, state, 503, "Command out of sequence"}
  end

  defp handle_line(_, state, "RCPT TO:" <> _) do
    {:response, state, 503, "Command out of sequence"}
  end

  defp handle_line(_, state, _) do
    {:response, state, 502, "Command not implemented"}
  end

  @spec receive_mail(%Connection{}, String.t(), map()) ::
          {:ok, Mail}
          | {:error, atom()}
  defp receive_mail(conn, from, params) do
    # TODO(indutny): implement it
    if Map.get(params, :body, :normal) != :normal do
      raise "8BITMIME not implemented yet"
    end

    case Map.get(params, :size, conn.max_mail_size) do
      size when size > conn.max_mail_size ->
        {:error, :max_size_exceeded}

      max_size ->
        mail = %Mail{from: from, to: [], max_size: max_size}
        {:ok, mail}
    end
  end

  @spec receive_rcpt(%Connection{}, %Mail{}, String.t(), map()) ::
          {:ok, %Mail{}}
          | {:error, atom()}
  defp receive_rcpt(_, mail, rcpt, _params) do
    # TODO(indutny): check that `rcpt` is in allowlist
    # 550 - if no such user
    # should also disallow outgoing email (different domain) unless
    # authorized.
    {:ok, Mail.add_recipient(mail, rcpt)}
  end

  @spec process_mail(%Mail{}) :: :ok
  defp process_mail(mail) do
    IO.inspect(mail)
    :ok
  end

  #
  # Helpers
  #

  defp get_line(conn, state) do
    case :gen_tcp.recv(conn.socket, 0, conn.read_timeout) do
      {:ok, line} ->
        case state do
          {:data, _} -> line
          _ -> line |> String.replace_trailing("\r\n", "")
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
end
