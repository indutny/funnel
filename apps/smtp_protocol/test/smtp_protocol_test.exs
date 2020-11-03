defmodule SMTPProtocolTest do
  use ExUnit.Case, async: true
  doctest SMTPProtocol

  describe "parse_mail_and_params" do
    test "should not allow SIZE parameter in RCPT" do
      assert SMTPProtocol.parse_mail_and_params("<a@b.com> SIZE=10", :rcpt) ==
               {:error, "Unknown mail parameter"}
    end

    test "should parse ALT-ADDRESS in both MAIL and RCPT" do
      assert SMTPProtocol.parse_mail_and_params(
               "<юникод@b.com> ALT-ADDRESS=unicode@b.com",
               :mail
             ) ==
               {:ok, "юникод@b.com", %{alt_address: "unicode@b.com"}}

      assert SMTPProtocol.parse_mail_and_params(
               "<юникод@b.com> ALT-ADDRESS=unicode+2Bok@b.com",
               :rcpt
             ) ==
               {:ok, "юникод@b.com", %{alt_address: "unicode+ok@b.com"}}
    end
  end
end
