defmodule FunnelServerTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  alias Funnel.Server
  alias Funnel.Client
  alias FunnelSMTP.Mail
  alias FunnelSMTPTest.MockScheduler

  doctest Server

  setup do
    scheduler = start_supervised!(MockScheduler)

    config = %Server.Config{
      certfile: "priv/keys/cert.pem",
      keyfile: "priv/keys/key.pem",
      dhfile: "priv/keys/dh.pem",
      mail_scheduler: {MockScheduler, scheduler}
    }

    {:ok, _pid, %{port: port, ref: ref}} = start_supervised({Server, config})

    %{server: ref, port: port}
  end

  test "should accept email from real client", %{server: server, port: port} do
    client =
      start_supervised!(
        {Client,
         %Client.Config{
           host: "mxloopback.dev",
           port: port,
           insecure: true
         }}
      )

    assert Client.connect(client) == :ok

    mail = Mail.new("allowed@sender")
    {:ok, mail} = Mail.add_forward(mail, "allowed@rcpt")
    mail = Mail.add_data(mail, "Hello!")

    assert Client.send(client, mail) == :ok

    assert Server.close(server) == :ok
  end
end
