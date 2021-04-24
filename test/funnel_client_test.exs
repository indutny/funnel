defmodule FunnelClientTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  alias Funnel.Client
  alias FunnelSMTP.Mail
  alias FunnelTest.MockServer

  doctest Client

  setup do
    start_supervised!(MockServer)

    :ok
  end

  test "should connect to server" do
    client =
      start_supervised!(
        {Client,
         %Client.Config{
           host: "mxloopback.dev",
           port: MockServer.get_port(),
           insecure: true
         }}
      )

    send =
      Task.async(fn ->
        assert Client.connect(client) == :ok

        mail = Mail.new("from@me")
        {:ok, mail} = Mail.add_forward(mail, "to@you")
        mail = Mail.add_data(mail, "Hello!")

        assert Client.send(client, mail) == :ok
      end)

    assert MockServer.accept() == :ok
    send_line!("220 Hello")
    assert MockServer.recv_line() == "EHLO funnel.localhost\r\n"
    send_line!("250 funnel.example greets funnel.localhost")
    assert MockServer.recv_line() == "MAIL FROM:<from@me>\r\n"
    send_line!("250 OK")
    assert MockServer.recv_line() == "RCPT TO:<to@you>\r\n"
    send_line!("250 OK")
    assert MockServer.recv_line() == "DATA\r\n"
    send_line!("354 Please continue")
    assert MockServer.recv_line() == "Hello!\r\n"
    assert MockServer.recv_line() == ".\r\n"
    send_line!("250 OK")

    Task.await(send)
  end

  def send_line!(line) do
    assert MockServer.send_line(line) == :ok
  end

  def send_lines!(lines) do
    for line <- lines do
      send_line!(line)
    end
  end
end
