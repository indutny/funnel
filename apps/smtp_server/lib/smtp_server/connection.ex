defmodule SMTPServer.Connection do
  require Logger

  alias SMTPServer.Connection
  alias SMTPServer.Mail

  @enforce_keys [:local_domain, :max_mail_size]
  defstruct [
    :local_domain,
    :remote_addr,
    :remote_domain,
    :max_mail_size,
    :socket,
    read_timeout: 5000
  ]

  @type t() :: %Connection{
          local_domain: String.t(),
          remote_addr: :inet.ip_address(),
          remote_domain: String.t(),
          max_mail_size: integer,
          socket: nil | :gen_tcp.socket(),
          read_timeout: integer()
        }

  @type state() :: :handshake | :main | {:rcpt, Mail} | {:data, Mail, :crlf | :lf}

  @type line_response ::
          {:no_response, state()}
          | {:response, state(), integer, String.t()}
          | :exit

  @doc """
  Start handshake with remote endpoint.
  """
  @spec serve(t()) :: :ok
  def serve(conn) do
    {:ok, {remote_addr, _}} = :inet.peername(conn.socket)
    {:ok, {:hostent, remote_domain, _, _, _, _}} = :inet.gethostbyaddr(remote_addr)

    Logger.info("Received new connection from #{remote_domain}")

    respond(conn, "220 #{conn.local_domain}")

    loop(:handshake, %Connection{
      conn
      | remote_addr: remote_addr,
        remote_domain: remote_domain
    })
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

  @spec handle_line(t(), state(), SMTPProtocol.command()) :: line_response()
  defp handle_line(conn, state, line)

  defp handle_line(_, :handshake, {:rset, "", _}) do
    {:response, :handshake, 250, "OK"}
  end

  defp handle_line(_, _, {:rset, "", _}) do
    {:response, :main, 250, "OK"}
  end

  defp handle_line(_, state, {:noop, "", _}) do
    {:response, state, 250, "OK"}
  end

  defp handle_line(conn, _, {:quit, "", _}) do
    respond(conn, "221 OK")
    :gen_tcp.shutdown(conn.socket, :write)
    :exit
  end

  defp handle_line(_, :handshake, {:helo, _domain, _}) do
    {:response, :main, 250, "OK"}
  end

  defp handle_line(conn, :handshake, {:ehlo, _domain, _}) do
    respond(conn, "250-#{conn.local_domain} greets #{conn.remote_domain}")
    # TODO(indutny): STARTTLS
    respond(conn, "250-8BITMIME")
    respond(conn, "250-PIPELINING")
    respond(conn, "250-SIZE #{conn.max_mail_size}")
    {:response, :main, 250, "SMTPUTF8"}
  end

  defp handle_line(_, :main, {:vrfy, _, _}) do
    # Not really supported
    {:response, :main, 252, "I will be happy to accept your message"}
  end

  defp handle_line(_, :main, {:help, _, _}) do
    # Not really supported
    {:response, :main, 214, "I'm so happy you asked"}
  end

  defp handle_line(conn, :main, {:mail_from, reverse_path, _}) do
    case SMTPProtocol.parse_mail_and_params(reverse_path, :mail) do
      {:ok, reverse_path, params} ->
        case receive_reverse_path(conn, reverse_path, params) do
          {:ok, mail} ->
            {:response, {:rcpt, mail}, 250, "OK"}

          {:error, :max_size_exceeded} ->
            {:response, :main, 552, "Mail exceeds maximum allowed size"}
        end

      {:error, :unknown_param} ->
        {:response, :main, 555, "MAIL FROM parameters not recognized or not implemented"}

      {:error, msg} ->
        {:response, :main, 553, msg}
    end
  end

  defp handle_line(conn, {:rcpt, mail}, {:rcpt_to, forward_path, _}) do
    case SMTPProtocol.parse_mail_and_params(forward_path, :rcpt) do
      {:ok, forward_path, params} ->
        {:ok, new_mail} = receive_forward_path(conn, mail, forward_path, params)
        {:response, {:rcpt, new_mail}, 250, "OK"}

      {:error, :unknown_param} ->
        {:response, :main, 555, "RCPT TO parameters not recognized or not implemented"}

      {:error, msg} ->
        {:response, {:rcpt, mail}, 553, msg}
    end
  end

  defp handle_line(_, {:rcpt, mail}, {:data, "", trailing}) do
    if Enum.empty?(mail.forward_paths) do
      {:response, {:rcpt, mail}, 554, "No valid recipients"}
    else
      {:response, {:data, mail, trailing}, 354, "Start mail input; end with <CRLF>.<CRLF>"}
    end
  end

  defp handle_line(_, {:data, mail, :crlf}, ".\r\n") do
    if Mail.has_exceeded_size?(mail) do
      Logger.info("Mail size exceeded")
      {:response, :main, 552, "Mail exceeds maximum allowed size"}
    else
      Logger.info("Got new mail")
      :ok = process_mail(mail)
      {:response, :main, 250, "OK"}
    end
  end

  defp handle_line(_, {:data, mail, _}, data) do
    data =
      with "." <> stripped <- data do
        stripped
      end

    trailing =
      if String.ends_with?(data, "\r\n") do
        :crlf
      else
        :lf
      end

    {:no_response, {:data, Mail.add_data(mail, data), trailing}}
  end

  defp handle_line(_, state, {:data, "", _}) do
    {:response, state, 503, "Command out of sequence"}
  end

  defp handle_line(_, state, {:rcpt_to, _, _}) do
    {:response, state, 503, "Command out of sequence"}
  end

  defp handle_line(_, state, {:unknown, line}) do
    Logger.info("Unknown command #{line}")
    {:response, state, 502, "Command not implemented"}
  end

  defp handle_line(conn, _, _) do
    respond(conn, "451 Server error")
    :gen_tcp.shutdown(conn.socket, :write)
    :exit
  end

  @spec receive_reverse_path(t(), String.t(), map()) ::
          {:ok, Mail}
          | {:error, atom()}
  defp receive_reverse_path(conn, reverse_path, params) do
    # TODO(indutny): should we bother about possible 7-bit encoding?
    case Map.get(params, :size, conn.max_mail_size) do
      size when size > conn.max_mail_size ->
        {:error, :max_size_exceeded}

      max_size ->
        mail = %Mail{
          reverse_path: {reverse_path, params},
          max_size: max_size
        }

        {:ok, mail}
    end
  end

  @spec receive_forward_path(t(), Mail.t(), String.t(), map()) ::
          {:ok, Mail.t()}
          | {:error, atom()}
  defp receive_forward_path(_, mail, forward_path, params) do
    # TODO(indutny): check that `forward_path` is in allowlist
    # 550 - if no such user
    # should also disallow outgoing email (different domain) unless
    # authorized.
    # NOTE: Allow case-insensitive Postmaster
    {:ok, Mail.add_forward_path(mail, {forward_path, params})}
  end

  @spec process_mail(Mail.t()) :: :ok
  defp process_mail(mail) do
    mail = Mail.trim_trailing_crlf(mail)

    IO.inspect(mail)
    :ok
  end

  #
  # Helpers
  #

  defp get_line(conn, state) do
    case :gen_tcp.recv(conn.socket, 0, conn.read_timeout) do
      {:ok, line} ->
        Logger.debug("#{conn.remote_domain} < #{String.trim_trailing(line)}")

        case state do
          {:data, _, _} ->
            line

          _ ->
            line
            |> SMTPProtocol.parse_command()
        end

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  defp respond(conn, line) do
    Logger.debug("#{conn.remote_domain} > #{line}")

    case :gen_tcp.send(conn.socket, line <> "\r\n") do
      :ok ->
        :ok

      {:error, :closed} ->
        exit(:shutdown)
    end
  end
end
