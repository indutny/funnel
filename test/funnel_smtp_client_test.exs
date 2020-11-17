defmodule FunnelSMTPClientTest do
  use ExUnit.Case, async: true
  doctest FunnelSMTP.Client

  alias FunnelSMTP.Client
  alias FunnelSMTP.Server
  alias FunnelSMTP.Mail

  alias FunnelSMTPTest.MockScheduler
  alias FunnelSMTPTest.MockConnection

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
      reverse: {"allowed@sender", %{}},
      forward: [{"allowed@rcpt", %{}}],
      data: "Hey!\r\n...are you okay?"
    }

    assert Client.handshake(client) == :ok
    assert Client.send(client, outgoing) == :ok
    assert Client.quit(client) == :ok

    assert {:ok, mail} = MockScheduler.pop(scheduler)
    assert mail.reverse == {"allowed@sender", %{size: 22}}
    assert mail.forward == [{"allowed@rcpt", %{}}]
    assert mail.data == outgoing.data
  end
end
