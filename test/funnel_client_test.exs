defmodule FunnelClientTest do
  use ExUnit.Case, async: true

  alias Funnel.Server
  alias Funnel.Client
  alias FunnelSMTP.Mail

  doctest Client

  setup do
    {:ok, _, %{port: port}} = start_supervised({Server, %Server.Config{}})

    %{port: port}
  end

  test "should connect to server", %{port: port} do
    client =
      start_supervised!(
        {Client,
         %Client.Config{
           host: "localhost",
           port: port
         }}
      )

    mail = Mail.new("i@am.here", %{}, "hello!")
    assert Client.send(client, mail) == :ok
  end
end
