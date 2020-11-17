defmodule FunnelSMTPTest do
  use ExUnit.Case, async: true
  doctest FunnelSMTP

  describe "parse_command" do
    test "should be case insensitive" do
      assert FunnelSMTP.parse_command("hElO domain\r\n") ==
               {:helo, "domain", :crlf}
    end

    test "should require domain for HELO" do
      assert FunnelSMTP.parse_command("HELO\r\n") ==
               {:unknown, "HELO"}
    end

    test "should not require domain for EHLO" do
      assert FunnelSMTP.parse_command("EHLO\r\n") == {:ehlo, "", :crlf}
    end

    test "should ignore whitespace before CRLF" do
      assert FunnelSMTP.parse_command("EHLO  \t \r\n") == {:ehlo, "", :crlf}
    end
  end

  describe "parse_mail_params" do
    test "should not allow SIZE parameter in RCPT" do
      assert FunnelSMTP.parse_mail_params("SIZE=10", :rcpt) ==
               {:error, :unknown_param}
    end

    test "should parse BODY in MAIL" do
      assert FunnelSMTP.parse_mail_and_params(
               "<a@b.com> BODY=7BIT",
               :mail
             ) ==
               {:ok, "a@b.com", %{body: :normal}}

      assert FunnelSMTP.parse_mail_and_params(
               "<a@b.com> BODY=8BITMIME",
               :mail
             ) ==
               {:ok, "a@b.com", %{body: :mime}}
    end

    test "should be case insensitive with regards to param names" do
      assert FunnelSMTP.parse_mail_params("sIZe=10", :mail) ==
               {:ok, %{size: 10}}
    end
  end
end
