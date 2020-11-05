defmodule SMTPProtocolTest do
  use ExUnit.Case, async: true
  doctest SMTPProtocol

  describe "parse_command" do
    test "should be case insensitive" do
      assert SMTPProtocol.parse_command("hElO domain\r\n") ==
               {:helo, "domain", "\r\n"}
    end

    test "should require domain for HELO" do
      assert SMTPProtocol.parse_command("HELO\r\n") ==
               {:unknown, "HELO"}
    end

    test "should not require domain for EHLO" do
      assert SMTPProtocol.parse_command("EHLO\r\n") == {:ehlo, "", "\r\n"}
    end

    test "should ignore whitespace before CRLF" do
      assert SMTPProtocol.parse_command("EHLO  \t \r\n") == {:ehlo, "", "\r\n"}
    end
  end

  describe "parse_mail_params" do
    test "should not allow SIZE parameter in RCPT" do
      assert SMTPProtocol.parse_mail_params("SIZE=10", :rcpt) ==
               {:error, :unknown_param}
    end

    test "should parse ALT-ADDRESS in both MAIL and RCPT" do
      [:mail, :rcpt]
      |> Enum.map(fn mode ->
        assert SMTPProtocol.parse_mail_params(
                 "ALT-ADDRESS=unicode@b.com",
                 mode
               ) ==
                 {:ok, %{alt_address: "unicode@b.com"}}
      end)
    end

    test "should parse xtext in ALT-ADDRESS" do
      assert SMTPProtocol.parse_mail_params(
               "ALT-ADDRESS=unicode+2Bok@b.com",
               :mail
             ) ==
               {:ok, %{alt_address: "unicode+ok@b.com"}}
    end

    test "should parse BODY in MAIL" do
      assert SMTPProtocol.parse_mail_and_params(
               "<a@b.com> BODY=7BIT",
               :mail
             ) ==
               {:ok, "a@b.com", %{body: :normal}}

      assert SMTPProtocol.parse_mail_and_params(
               "<a@b.com> BODY=8BITMIME",
               :mail
             ) ==
               {:ok, "a@b.com", %{body: :mime}}
    end

    test "should be case insensitive with regards to param names" do
      assert SMTPProtocol.parse_mail_params("sIZe=10", :mail) ==
               {:ok, %{size: 10}}
    end
  end
end
