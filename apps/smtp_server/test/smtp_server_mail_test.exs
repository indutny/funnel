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

    test "should remove trailing LF" do
      mail = %SMTPServer.Mail{
        reverse_path: {"a@b.com", %{}},
        max_size: 100
      }

      mail = SMTPServer.Mail.add_data(mail, "hello\n\n")
      assert mail.data == "hello\n\n"

      mail = SMTPServer.Mail.trim_trailing_crlf(mail)
      assert mail.data == "hello\n"
    end

    test "should leave empty mail data unchanged" do
      mail = %SMTPServer.Mail{
        reverse_path: {"a@b.com", %{}},
        max_size: 100
      }

      assert mail.data == ""

      mail = SMTPServer.Mail.trim_trailing_crlf(mail)
      assert mail.data == ""
    end
  end
end
