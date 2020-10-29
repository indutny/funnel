defmodule SMTPServerTest do
  use ExUnit.Case, async: true
  doctest SMTPServer

  @moduletag capture_log: true

  setup do
    opts = [port_listener: self()]
    start_supervised!({Task, fn ->
      SMTPServer.listen(0, opts)
    end})

    port = receive do
      {:port, port} -> port
    after
      1000 -> exit(:timed_out)
    end

    {:ok, socket} = :gen_tcp.connect(
      '127.0.0.1', port, [:binary, packet: :line, active: false])

    %{socket: socket}
  end

  test "should accept HELO", %{socket: socket} do
    assert recv_line(socket) == "220 funnel.example\r\n"
    send_line(socket, "HELO iam.test")
    assert recv_line(socket) == "250 OK\r\n"
  end

  test "should accept EHLO without domain", %{socket: socket} do
    assert recv_line(socket) == "220 funnel.example\r\n"
    send_line(socket, "EHLO")
    assert recv_line(socket) == "250-funnel.example greets localhost\r\n"
  end

  test "should receive mail", %{socket: socket} do
    assert recv_line(socket) == "220 funnel.example\r\n"
    send_line(socket, "EHLO iam.test")
    assert recv_line(socket) == "250-funnel.example greets localhost\r\n"
    assert recv_line(socket) == "250-8BITMIME\r\n"
    assert recv_line(socket) == "250-SIZE 35882577\r\n"
    assert recv_line(socket) == "250 SMTPUTF8\r\n"

    send_line(socket, "MAIL FROM:<spam@example.com>")
    assert recv_line(socket) == "250 OK\r\n"
  end

  defp send_line(socket, line) do
    :ok = :gen_tcp.send(socket, line <> "\r\n")
    line
  end

  defp recv_line(socket) do
    {:ok, line} = :gen_tcp.recv(socket, 0, 1000)
    line
  end
end
