defmodule SMTPServerTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  doctest SMTPServer

  # Just a constant
  @handshake [
    "250-funnel.example greets localhost",
    "250-8BITMIME",
    "250-PIPELINING",
    "250-SIZE 31457280",
    "250 SMTPUTF8"
  ]

  setup do
    opts = [port_listener: self()]

    start_supervised!(
      {Task,
       fn ->
         SMTPServer.listen(0, opts)
       end}
    )

    port =
      receive do
        {:port, port} -> port
      after
        1000 -> exit(:timed_out)
      end

    {:ok, socket} =
      :gen_tcp.connect(
        '127.0.0.1',
        port,
        [:binary, packet: :line, active: false]
      )

    %{socket: socket}
  end

  describe "NOOP" do
    test "should ignore NOOP during handshake", %{socket: socket} do
      assert recv_line(socket) == "220 funnel.example"

      send_line(socket, "NOOP")
      assert recv_line(socket) == "250 OK"

      handshake(socket, :skip_first)
    end

    test "should ignore NOOP after handshake", %{socket: socket} do
      handshake(socket)

      send_line(socket, "NOOP")
      assert recv_line(socket) == "250 OK"
    end
  end

  describe "RSET" do
    test "should treat RSET as NOOP during handshake", %{socket: socket} do
      assert recv_line(socket) == "220 funnel.example"

      send_line(socket, "RSET")
      assert recv_line(socket) == "250 OK"

      handshake(socket, :skip_first)
    end

    # TODO(indutny): RSET during mail
  end

  test "should close connection on QUIT", %{socket: socket} do
    handshake(socket)

    send_line(socket, "QUIT")
    assert recv_line(socket) == "221 OK"

    assert is_closed(socket)
  end

  test "should support VRFY and HELP", %{socket: socket} do
    handshake(socket)

    send_line(socket, "VRFY something")
    assert recv_line(socket) == "252 I will be happy to accept your message"

    send_line(socket, "HELP something")
    assert recv_line(socket) == "214 I'm so happy you asked"
  end

  test "should enforce size limit", %{socket: socket} do
    handshake(socket)

    send_line(socket, "MAIL FROM:<spam@example.com> SIZE=10000000000")
    assert recv_line(socket) == "552 Mail exceeds maximum allowed size"
  end

  test "should disallow mail without recipients", %{socket: socket} do
    handshake(socket)

    send_line(socket, "MAIL FROM:<spam@example.com> SIZE=100")
    assert recv_line(socket) == "250 OK"
    send_line(socket, "DATA")
    assert recv_line(socket) == "554 No valid recipients"
  end

  test "should receive mail", %{socket: socket} do
    handshake(socket)

    send_line(socket, "MAIL FROM:<spam@example.com> SIZE=100")
    assert recv_line(socket) == "250 OK"
    send_line(socket, "RCPT TO:<a@funnel.example>")
    assert recv_line(socket) == "250 OK"
    send_line(socket, "RCPT TO:<b@funnel.example>")
    assert recv_line(socket) == "250 OK"
    send_line(socket, "DATA")
    assert recv_line(socket) == "354 Start mail input; end with <CRLF>.<CRLF>"
    send_line(socket, "Hey!")
    send_line(socket, "How are you?\n.")
    send_line(socket, ".")
  end

  # Helpers

  defp handshake(socket, mode \\ :normal) do
    case mode do
      :normal ->
        assert recv_line(socket) == "220 funnel.example"

      :skip_first ->
        :ok
    end

    send_line(socket, "EHLO iam.test")
    assert recv_lines(socket, length(@handshake)) == @handshake
  end

  defp send_line(socket, line) do
    :ok = :gen_tcp.send(socket, line <> "\r\n")
    line
  end

  defp recv_lines(socket, count) do
    1..count
    |> Enum.map(fn _ ->
      {:ok, line} = :gen_tcp.recv(socket, 0, 1000)
      assert String.ends_with?(line, "\r\n"), "Line has to end with CRLF"
      String.replace(line, ~r/\r\n$/, "")
    end)
  end

  defp recv_line(socket) do
    [line] = recv_lines(socket, 1)
    line
  end

  defp is_closed(socket) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:error, :closed} -> true
      _ -> false
    end
  end
end
