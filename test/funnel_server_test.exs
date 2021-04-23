defmodule FunnelServerTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  alias Funnel.Server

  doctest Server

  setup do
    config = %Server.Config{
      certfile: "priv/keys/cert.pem",
      keyfile: "priv/keys/key.pem",
      dhfile: "priv/keys/dh.pem"
    }

    {:ok, _, %{port: port}} = start_supervised({Server, config})

    %{port: port}
  end
end
