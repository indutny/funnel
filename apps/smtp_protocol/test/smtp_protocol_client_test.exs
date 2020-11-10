defmodule SMTPProtocolClientTest do
  use ExUnit.Case, async: true
  doctest SMTPProtocol.Client

  alias SMTPProtocol.Client
  alias SMTPProtocol.Server
  alias SMTPProtocol.Mail

  alias SMTPProtocolTest.MockScheduler
  alias SMTPProtocolTest.MockConnection

  @moduletag capture_log: true

  setup do
    scheduler = start_supervised!(MockScheduler)

    server =
      start_supervised!(
        {Server,
         %Server.Config{
           local_domain: "server.example",
           remote_domain: "client.example",
           max_mail_size: 1024,
           mail_scheduler: {MockScheduler, scheduler}
         }}
      )

    conn = start_supervised!({MockConnection, server})

    %{server: server, scheduler: scheduler, conn: {MockConnection, conn}}
  end

  test "should send mail", %{conn: conn, scheduler: scheduler} do
    config = %Client.Config{
      local_domain: "client.example"
    }

    outgoing = %Mail{
      reverse: {"i@client.example", %{}},
      forward: [{"you@server.example", %{}}],
      data: "Hey!\r\n...are you okay?"
    }

    assert Client.handshake(config, conn) == :ok
    assert Client.send(config, conn, outgoing) == :ok

    assert {:mail, mail} = MockScheduler.pop(scheduler)
    assert mail == outgoing
  end
end
