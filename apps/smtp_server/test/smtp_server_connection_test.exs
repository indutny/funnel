defmodule SMTPServerConnectionTest do
  use ExUnit.Case, async: true
  doctest SMTPServer.Connection

  alias SMTPServer.Connection

  @moduletag capture_log: true
  @max_mail_size 1024
  @ok {:normal, 250, "OK"}

  # Just a constant
  @handshake {:normal, 250,
              [
                "funnel.example greets remote.example",
                "8BITMIME",
                "PIPELINING",
                "SIZE #{@max_mail_size}",
                "SMTPUTF8"
              ]}

  setup do
    pid =
      start_supervised!(
        {Connection,
         %{
           local_domain: "funnel.example",
           remote_domain: "remote.example",
           max_mail_size: @max_mail_size
         }}
      )

    %{conn: pid}
  end

  describe "NOOP" do
    test "should ignore NOOP during handshake", %{conn: conn} do
      assert Connection.handshake(conn) ==
               {:normal, 220, "Welcome to funnel.example"}

      assert send_line(conn, "NOOP") == @ok

      handshake!(conn, :skip_first)
    end

    test "should ignore NOOP after handshake", %{conn: conn} do
      handshake!(conn)

      assert send_line(conn, "NOOP") == @ok
    end
  end

  describe "RSET" do
    test "should treat RSET as NOOP during handshake", %{conn: conn} do
      assert Connection.handshake(conn) ==
               {:normal, 220, "Welcome to funnel.example"}

      assert send_line(conn, "RSET") == @ok

      handshake!(conn, :skip_first)
    end

    # TODO(indutny): RSET during mail
  end

  test "should close connection on QUIT", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "QUIT") == {:shutdown, 221, "OK"}
  end

  test "should support VRFY and HELP", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "VRFY something") ==
             {:normal, 252, "I will be happy to accept your message"}

    assert send_line(conn, "HELP something") ==
             {:normal, 214, "I'm so glad you asked. Check RFC 5321"}
  end

  test "should not allow out of sequence DATA/RCPT TO", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "DATA") == {:normal, 503, "Command out of sequence"}

    assert send_line(conn, "RCPT TO:<a@a.com>") ==
             {:normal, 503, "Command out of sequence"}
  end

  test "should enforce size limit", %{conn: conn} do
    handshake!(conn)

    assert send_line(
             conn,
             "MAIL FROM:<spam@example.com> " <>
               "SIZE=#{2 * @max_mail_size}"
           ) ==
             {:normal, 552, "Mail exceeds maximum allowed size"}
  end

  test "should disallow mail without recipients", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "MAIL FROM:<spam@example.com> SIZE=100") == @ok

    assert send_line(conn, "DATA") ==
             {:normal, 554, "No valid recipients"}
  end

  test "should receive mail", %{conn: conn} do
    handshake!(conn)

    assert send_lines(conn, [
             "MAIL FROM:<spam@example.com> SIZE=100",
             "RCPT TO:<a@funnel.example>",
             "RCPT TO:<b@funnel.example>",
             "DATA"
           ]) == [
             @ok,
             @ok,
             @ok,
             {:normal, 354, "Start mail input; end with <CRLF>.<CRLF>"}
           ]

    assert send_lines(conn, [
             "Hey!",
             ".How are you?\n.",
             "."
           ]) == [
             :no_response,
             :no_response,
             @ok
           ]
  end

  # Helpers

  defp handshake!(conn, mode \\ :normal) do
    case mode do
      :normal ->
        assert Connection.handshake(conn) ==
                 {:normal, 220, "Welcome to funnel.example"}

      :skip_first ->
        :ok
    end

    assert send_line(conn, "EHLO iam.test") == @handshake
  end

  def send_line(conn, line) do
    Connection.respond_to(conn, line <> "\r\n")
  end

  def send_lines(conn, lines) do
    lines
    |> Enum.map(&send_line(conn, &1))
  end
end
