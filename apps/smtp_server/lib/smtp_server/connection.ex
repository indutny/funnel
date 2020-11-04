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

  @type t() :: %Connection{
          local_domain: String.t(),
          remote_domain: String.t(),
          max_mail_size: integer,
          socket: nil | :gen_tcp.socket(),
          read_timeout: integer()
        }

  @type state() :: :handshake | :main | {:rcpt, Mail} | {:data, Mail}

  @type line_response ::
          {:no_response, state()}
          | {:response, state(), integer, String.t()}
          | :exit

  @doc """
  Start handshake with remote endpoint.
  """
  @spec serve(t()) :: :ok
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

      :exit ->
        exit(:shutdown)
    end
  end

  @spec handle_line(t(), state(), String.t()) :: line_response()
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
    :exit
  end

  defp handle_line(conn, :handshake, line) do
    case SMTPProtocol.parse_handshake(line) do
      {:ok, :extended, _} ->
        respond(conn, "250-#{conn.local_domain} greets #{conn.remote_domain}")
        # TODO(indutny): STARTTLS
        respond(conn, "250-8BITMIME")
        respond(conn, "250-PIPELINING")
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

  defp handle_line(conn, :main, "MAIL FROM:" <> reverse_path) do
    case SMTPProtocol.parse_mail_and_params(reverse_path, :mail) do
      {:ok, reverse_path, params} ->
        case receive_mail(conn, reverse_path, params) do
          {:ok, mail} ->
            {:response, {:rcpt, mail}, 250, "OK"}

          {:error, :max_size_exceeded} ->
            {:response, :main, 552, "Mail exceeds maximum allowed size"}
        end

      {:error, msg} ->
        {:response, :main, 553, msg}
    end
  end

  defp handle_line(conn, {:rcpt, mail}, "RCPT TO:" <> forward_path) do
    case SMTPProtocol.parse_mail_and_params(forward_path, :rcpt) do
      {:ok, forward_path, params} ->
        {:ok, new_mail} = receive_forward_path(conn, mail, forward_path, params)
        {:response, {:rcpt, new_mail}, 250, "OK"}

      {:error, msg} ->
        {:response, {:rcpt, mail}, 553, msg}
    end
  end

  defp handle_line(_, {:rcpt, mail}, "DATA") do
    case mail.forward_paths do
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

  @spec receive_mail(t(), String.t(), map()) ::
          {:ok, Mail}
          | {:error, atom()}
  defp receive_mail(conn, reverse_path, params) do
    # TODO(indutny): should we bother about possible 7-bit encoding?
    case Map.get(params, :size, conn.max_mail_size) do
      size when size > conn.max_mail_size ->
        {:error, :max_size_exceeded}

      max_size ->
        mail = %Mail{
          reverse_path: reverse_path,
          max_size: max_size
        }
        {:ok, mail}
    end
  end

  @spec receive_forward_path(t(), Mail.t(), String.t(), map()) ::
          {:ok, Mail.t()}
          | {:error, atom()}
  defp receive_forward_path(_, mail, forward_path, _params) do
    # TODO(indutny): check that `forward_path` is in allowlist
    # 550 - if no such user
    # should also disallow outgoing email (different domain) unless
    # authorized.
    {:ok, Mail.add_forward_path(mail, forward_path)}
  end

  @spec process_mail(Mail.t()) :: :ok
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
