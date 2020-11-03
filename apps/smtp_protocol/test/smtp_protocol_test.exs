defmodule SMTPProtocolTest do
  use ExUnit.Case, async: true
  doctest SMTPProtocol

  describe "parse_mail_and_params" do
    test "should not allow SIZE parameter in RCPT" do
      assert SMTPProtocol.parse_mail_and_params("<a@b.com> SIZE=10", :rcpt) ==
               {:error, "Unknown mail parameter"}
    end
  end
end
