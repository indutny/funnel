defmodule SMTPServerMailTest do
  use ExUnit.Case, async: true

  doctest SMTPServer.Mail

  describe "trim_trailing_crlf" do
    test "should remove trailing CRLF" do
      mail = %SMTPServer.Mail{
        reverse_path: {"a@b.com", %{}},
        max_size: 100
      }

      mail = SMTPServer.Mail.add_data(mail, "hello\r\n\r\n")
      assert mail.data == "hello\r\n\r\n"

      mail = SMTPServer.Mail.trim_trailing_crlf(mail)
      assert mail.data == "hello\r\n"
    end
  end
end
