defmodule SMTPServerMailTest do
  use ExUnit.Case, async: true

  alias SMTPProtocol.Mail
  doctest Mail

  describe "trim_trailing_crlf" do
    test "should remove trailing CRLF" do
      mail = Mail.new("a@b.com")

      mail = Mail.add_data(mail, "hello\r\n\r\n")
      assert mail.data == "hello\r\n\r\n"

      mail = Mail.trim_trailing_crlf(mail)
      assert mail.data == "hello\r\n"
    end
  end
end
