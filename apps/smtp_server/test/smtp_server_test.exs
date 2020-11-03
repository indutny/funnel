defmodule SMTPServerTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  doctest SMTPServer

  # Just a constant
  @handshake [
    "250-funnel.example greets localhost\r\n",
    "250-8BITMIME\r\n",
    "250-SIZE 31457280\r\n",
    "250 SMTPUTF8\r\n"
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

    assert recv_line(socket) == "220 funnel.example\r\n"
    send_line(socket, "EHLO iam.test")
    assert recv_lines(socket, length(@handshake)) == @handshake

    %{socket: socket}
  end

  test "should enforce size limit", %{socket: socket} do
    send_line(socket, "MAIL FROM:<spam@example.com> SIZE=10000000000")
    assert recv_line(socket) == "552 Mail exceeds maximum allowed size\r\n"
  end

  test "should receive mail", %{socket: socket} do
    send_line(socket, "MAIL FROM:<spam@example.com> SIZE=100")
    assert recv_line(socket) == "250 OK\r\n"
  end

  # Helpers

  defp send_line(socket, line) do
    :ok = :gen_tcp.send(socket, line <> "\r\n")
    line
  end

  defp recv_lines(socket, count) do
    1..count
    |> Enum.map(fn _ ->
      {:ok, line} = :gen_tcp.recv(socket, 0, 1000)
      line
    end)
  end

  defp recv_line(socket) do
    [line] = recv_lines(socket, 1)
    line
  end
end
