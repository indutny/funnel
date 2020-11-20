defmodule FunnelSMTPAddressTest do
  use ExUnit.Case, async: true
  alias FunnelSMTP.Address

  doctest Address

  @pattern Address.compile()

  test "should match deprecated A-D-L" do
    assert %{
             "a_d_l" => "@domain.com,@sub.domain.com",
             "mailbox" => "email@address.com",
             "local_part" => "email",
             "domain" => "address.com"
           } = capture("<@domain.com,@sub.domain.com:email@address.com>")
  end

  describe "domain" do
    test "should match IPV4 domains" do
      assert %{
               "domain" => "",
               "addr" => "[127.0.0.1]",
               "ipv4_addr" => "127.0.0.1"
             } = capture("<email@[127.0.0.1]>")
    end

    test "should match IPV6 domains" do
      assert %{
               "addr" => "[IPv6:::1]",
               "ipv6_addr" => "::1"
             } = capture("<email@[IPv6:::1]>")
    end

    test "should match general address" do
      assert %{
               "domain" => "",
               "addr" => "[IPv42:why]",
               "general_addr" => "IPv42:why"
             } = capture("<email@[IPv42:why]>")
    end

    test "should match regular domain names" do
      assert %{
               "domain" => "domain.subdomain.com",
               "addr" => ""
             } = capture("<email@domain.subdomain.com>")
    end

    test "should match domain names with multiple digits" do
      assert %{
               "domain" => "domain.s4223.com",
               "addr" => ""
             } = capture("<email@domain.s4223.com>")
    end
  end

  describe "local_part" do
    test "should match quoted local part" do
      assert %{
               "quoted_string" => "\"quoted@-email\""
             } = capture("<\"quoted@-email\"@domain.com>")
    end

    test "should match dot local part" do
      assert %{
               "dot_string" => "a.b+c"
             } = capture("<a.b+c@domain.com>")
    end
  end

  defp capture(email) do
    Regex.named_captures(@pattern, email)
  end
end
