defmodule FunnelServerTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  doctest Funnel.Server
end
