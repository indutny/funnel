defmodule SMTPServer.Client do
  @enforce_keys [:local_domain, :max_mail_size]
  defstruct [:local_domain, :max_mail_size, :socket, read_timeout: 5000]

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

    receive_mail(client)
  end

  defp get_line(client) do
    case :gen_tcp.recv(client.socket, 0, client.read_timeout) do
      {:ok, line} ->
        line
        |> String.replace_trailing("\r\n", "")

      {:error, :closed} ->
        exit(:shutdown)
    end
  end

  defp respond(client, line) do
    :ok = :gen_tcp.send(client.socket, line <> "\r\n")
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

        mail = Mail.add_recipient(mail, rcpt)
        IO.inspect(mail)
        recv_mail_recipient(client, mail)
    end
  end
end
