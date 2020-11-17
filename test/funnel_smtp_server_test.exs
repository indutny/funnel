defmodule FunnelSMTPServerTest do
  use ExUnit.Case, async: true
  doctest FunnelSMTP.Server

  alias FunnelSMTP.Server
  alias FunnelSMTPTest.MockScheduler

  @moduletag capture_log: true
  @max_mail_size 1024
  @ok {:normal, 250, "OK"}

  # Just a constant
  @handshake {:normal, 250,
              [
                "funnel.example greets remote.example",
                "8BITMIME",
                "PIPELINING",
                "SIZE #{@max_mail_size}"
              ]}

  setup do
    scheduler = start_supervised!(MockScheduler)

    pid =
      start_supervised!(
        {Server,
         %Server.Config{
           local_domain: "funnel.example",
           remote_domain: "remote.example",
           max_mail_size: @max_mail_size,
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

    {:mail, mail} = MockScheduler.pop(scheduler)
    assert mail.reverse == {"allowed@sender", %{size: 100}}

    assert mail.forward == [
             {"second@rcpt", %{}},
             {"allowed@rcpt", %{}}
           ]

    assert mail.data == "Hey!\r\nHow are you?\n."
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
             {:normal, 450, "Please solve the challenge to proceed"}

    # But allow empty reverse path
    assert send_line(conn, "MAIL FROM:<>") == @ok
  end

  test "should check forward path against forwardlist", %{conn: conn} do
    handshake!(conn)

    assert send_line(conn, "MAIL FROM:<allowed@sender>") == @ok

    assert send_line(conn, "RCPT TO:<unknown@rcpt>") ==
             {:normal, 550, "Mailbox not found"}

    # But allow postmaster
    assert send_line(conn, "RCPT TO:<postmaster>") == @ok
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
end
