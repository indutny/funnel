defmodule FunnelSMTPMailTest do
  use ExUnit.Case, async: true

  alias FunnelSMTP.Mail

  doctest Mail

  describe "add_trace" do
    test "should be case insensitive" do
      mail =
        FunnelSMTP.Mail.new("a@b.com", %{}, "ohai")
        |> FunnelSMTP.Mail.add_trace(%FunnelSMTP.Mail.Trace{
          source_name: "source.com",
          source_addr: "1.2.3.4",
          local_name: "local.com",
          local_addr: "4.3.2.1",
          timestamp: ~U[1984-02-16 07:06:40Z]
        })

      assert mail.data ==
               Enum.join(
                 [
                   "Return-Path: <a@b.com>",
                   "Received: from source.com (1.2.3.4)",
                   "          by local.com (4.3.2.1);",
                   "          16 Feb 1984 07:06:40 +0000",
                   "ohai"
                 ],
                 "\r\n"
               )
    end
  end
end
