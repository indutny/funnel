defmodule FunnelServerTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  alias Funnel.Server

  doctest Server

  setup do
    {:ok, _, %{port: port}} = start_supervised({Server, %Server.Config{}})

    %{port: port}
  end
end
