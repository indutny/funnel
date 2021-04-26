defmodule FunnelSMTPServerTest do
  use ExUnit.Case, async: true
  doctest FunnelSMTP.Server

  alias FunnelSMTP.Server
  alias FunnelSMTPTest.MockScheduler

  @moduletag capture_log: true
  @max_mail_size 1024
  @max_anonymous_mail_size 16
  @ok {:normal, 250, "OK"}

  # Just a constant
  @handshake {:normal, 250,
              [
                "funnel.example greets iam.test (4.3.2.1)",
                "8BITMIME",
                "PIPELINING",
                "SIZE #{@max_mail_size}",
                "STARTTLS"
              ]}

  setup do
    scheduler = start_supervised!(MockScheduler)

    pid =
      start_supervised!(
        {Server,
         %Server.Config{
           local_domain: "funnel.example",
           local_addr: "1.2.3.4",
           remote_domain: "remote.example",
           remote_addr: "4.3.2.1",
           challenge_url: "https://funnel.example/",
           max_mail_size: @max_mail_size,
           max_anonymous_mail_size: @max_anonymous_mail_size,
           mail_scheduler: {MockScheduler, scheduler}
         }}
      )

    %{conn: pid, scheduler: scheduler}
  end

  describe "NOOP" do
    test "should ignore NOOP during handshake", %{conn: conn} do
      assert Server.handshake(conn) ==
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
      assert Server.handshake(conn) ==
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
             "MAIL FROM:<allowed@sender> " <>
               "SIZE=#{2 * @max_mail_size}"
           ) ==
             {:normal, 552, "Mail exceeds maximum allowed size"}
  end

  test "should disallow mail without recipients", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "MAIL FROM:<allowed@sender>") == @ok

    assert send_line(conn, "DATA") ==
             {:normal, 554, "No valid recipients"}
  end

  test "should receive mail", %{conn: conn, scheduler: scheduler} do
    handshake!(conn)

    assert send_lines(conn, [
             "MAIL FROM:<allowed@sender> SIZE=100",
             "RCPT TO:<allowed@rcpt>",
             "RCPT TO:<second@rcpt>",
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

    assert {:ok, mail} = MockScheduler.pop(scheduler)
    {reverse_path, reverse_ext} = mail.reverse
    assert reverse_ext == %{size: 100}
    assert reverse_path =~ ~r/RS0=FUN=\d+=sender=allowed@funnel.example/

    assert mail.forward == [
             {"second@rcpt", %{}},
             {"allowed@rcpt", %{}}
           ]

    check_lines!(mail.data, [
      ~r/Return-Path: <SRS0=FUN=\d+=sender=allowed@funnel.example>/,
      "Received: from iam.test (4.3.2.1)",
                 "          by funnel.example (1.2.3.4);",
                 "          16 Feb 1984 07:06:40 +0000",
      "Hey!",
      "How are you?\n."
    ])
  end

  test "should limit recipient count", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "MAIL FROM:<allowed@sender>") == @ok

    for _ <- 0..99 do
      assert send_line(conn, "RCPT TO:<allowed@rcpt>") == @ok
    end

    assert send_line(conn, "RCPT TO:<allowed@rcpt>") ==
             {:normal, 452, "Too many recipients"}
  end

  test "should check reverse path against allowlist", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "MAIL FROM:<disallowed@sender>") ==
             {:normal, 550,
              "Please solve a challenge to proceed: " <>
                "https://funnel.example/?source=disallowed@sender"}

    # But allow empty reverse path
    assert send_line(conn, "MAIL FROM:<>") == @ok
  end

  test "should apply different size limit for empty reverse path", %{conn: conn} do
    handshake!(conn)

    assert send_lines(conn, [
             "MAIL FROM:<>",
             "RCPT TO:<postmaster>",
             "DATA"
           ]) == [
             @ok,
             @ok,
             {:normal, 354, "Start mail input; end with <CRLF>.<CRLF>"}
           ]

    assert send_lines(conn, [
             "Somewhat longer email. Definitely > 16 characters",
             "."
           ]) == [
             :no_response,
             {:normal, 552, "Mail exceeds maximum allowed size"}
           ]
  end

  test "should check forward path against forwardlist", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "MAIL FROM:<allowed@sender>") == @ok

    assert send_line(conn, "RCPT TO:<unknown@rcpt>") ==
             {:normal, 550, "Mailbox not found"}

    # But allow postmaster
    assert send_line(conn, "RCPT TO:<postmaster>") == @ok
  end

  test "should check command line size", %{conn: conn} do
    handshake!(conn)

    assert send_lines(conn, [
             String.duplicate("X", 510),
             String.duplicate("X", 511)
           ]) == [
             {:normal, 502, "Command not implemented"},
             {:shutdown, 500, "Command line too long"}
           ]
  end

  test "should check text line size", %{conn: conn} do
    handshake!(conn)

    assert send_lines(conn, [
             "MAIL FROM:<>",
             "RCPT TO:<postmaster>",
             "DATA",
             "." <> String.duplicate("X", 998),
             "." <> String.duplicate("X", 999)
           ]) == [
             @ok,
             @ok,
             {:normal, 354, "Start mail input; end with <CRLF>.<CRLF>"},
             :no_response,
             {:shutdown, 500, "Text line too long"}
           ]
  end

  # Helpers

  defp handshake!(conn, mode \\ :normal) do
    case mode do
      :normal ->
        assert Server.handshake(conn) ==
                 {:normal, 220, "Welcome to funnel.example"}

      :skip_first ->
        :ok
    end

    assert send_line(conn, "EHLO iam.test") == @handshake
  end

  def send_line(conn, line) do
    Server.respond_to(conn, line <> "\r\n")
  end

  def send_lines(conn, lines) do
    lines
    |> Enum.map(&send_line(conn, &1))
  end

  defp check_lines!(actual, expected) do
    actual = String.split(actual, "\r\n")

    assert length(actual) == length(expected)

    Enum.zip(actual, expected)
    |> Enum.all?(fn {actual, expected} ->
      assert actual =~ expected
    end)
  end
end
