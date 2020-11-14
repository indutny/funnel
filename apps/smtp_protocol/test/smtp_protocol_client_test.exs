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

    config = %Client.Config{
      local_domain: "client.example"
    }

    client =
      start_supervised!(%{
        id: Client,
        start: {Client, :start_link, [config, {MockConnection, conn}]}
      })

    %{client: client, scheduler: scheduler}
  end

  test "should send mail", %{client: client, scheduler: scheduler} do
    outgoing = %Mail{
      reverse: {"i@client.example", %{}},
      forward: [{"you@server.example", %{}}],
      data: "Hey!\r\n...are you okay?"
    }

    assert Client.handshake(client) == :ok
    assert Client.send(client, outgoing) == :ok
    assert Client.quit(client) == :ok

    assert {:mail, mail} = MockScheduler.pop(scheduler)
    assert mail.reverse == {"i@client.example", %{size: 22}}
    assert mail.forward == [{"you@server.example", %{}}]
    assert mail.data == outgoing.data
  end
end
