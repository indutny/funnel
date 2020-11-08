defmodule SMTPProtocol do
  @moduledoc """
  SMTP protocol helpers.
  """

  @type reverse_params :: map()
  @type forward_params :: map()
  @type mail_path :: :null | :postmaster | String.t()

  @type command_kind ::
          :helo | :ehlo | :mail_from | :rcpt_to | :data | :rset | :noop | :quit | :vrfy | :help
  @type command_extra :: String.t()
  @type command_trailing :: :crlf | :lf
  @type command :: {command_kind(), command_extra(), command_trailing()}

  @commands %{
    ~r/^HELO\s/i => :helo,
    ~r/^EHLO(\s|$)/i => :ehlo,
    ~r/^MAIL FROM:/i => :mail_from,
    ~r/^RCPT TO:/i => :rcpt_to,
    ~r/^DATA(\s|$)/i => :data,
    ~r/^RSET(\s|$)/i => :rset,
    ~r/^NOOP(\s|$)/i => :noop,
    ~r/^QUIT(\s|$)/i => :quit,
    ~r/^VRFY(\s|$)/i => :vrfy,
    ~r/^HELP(\s|$)/i => :help
  }

  @doc ~S"""
  Parses the command.

  ## Examples

      iex> SMTPProtocol.parse_command("EHLO domain\r\n")
      {:ehlo, "domain", :crlf}

      iex> SMTPProtocol.parse_command("MAIL FROM:<a@b.com> A=1 B=2\r\n")
      {:mail_from, "<a@b.com> A=1 B=2", :crlf}

      iex> SMTPProtocol.parse_command("RCPT TO:<a@b.com> A=1 B=2\r\n")
      {:rcpt_to, "<a@b.com> A=1 B=2", :crlf}

      iex> SMTPProtocol.parse_command("DATA\r\n")
      {:data, "", :crlf}

  NOTE that for commands ending with "\n" it returns different trailing string

      iex> SMTPProtocol.parse_command("DATA\n")
      {:data, "", :lf}
  """
  @spec parse_command(String.t()) :: command() | {:unknown, String.t()}
  def parse_command(line) do
    [_, line, tail] = Regex.run(~r/^(.*?)\s*?(\r\n|\n)$/, line)

    tail =
      case tail do
        "\r\n" -> :crlf
        "\n" -> :lf
      end

    # 5231 4.1.1 - In the interest of improved interoperability, SMTP
    # receivers SHOULD tolerate trailing white space before the
    # terminating <CRLF>.
    Enum.find_value(@commands, {:unknown, line}, fn {pattern, type} ->
      case String.split(line, pattern, parts: 2) do
        ["", extra] ->
          {type, extra, tail}

        _ ->
          false
      end
    end)
  end

  @doc ~S"""
  Parses mail and params from a single string.

  ## Examples

      iex> SMTPProtocol.parse_mail_and_params("<a@b.com> SIZE=10", :mail)
      {:ok, "a@b.com", %{size: 10}}

      iex> SMTPProtocol.parse_mail_and_params("not an email", :rcpt)
      {:error, "Invalid mail path"}
  """
  def parse_mail_and_params(str, side) do
    {path, params} =
      case String.split(str, " ", parts: 2) do
        [path] -> {path, ""}
        [path, params] -> {path, params}
      end

    with {:ok, mailbox} <- SMTPProtocol.parse_mail_path(path, side),
         {:ok, params} <- SMTPProtocol.parse_mail_params(params, side) do
      {:ok, mailbox, params}
    end
  end

  @doc ~S"""
  Parses the given mail path.

  ## Examples

  Usual email addresses:

      iex> SMTPProtocol.parse_mail_path("<hello@world.com>", :mail)
      {:ok, "hello@world.com"}

  Deprecated but supported source path part of the address:

      iex> SMTPProtocol.parse_mail_path("<@b, @c:hello@world.com>", :mail)
      {:ok, "hello@world.com"}

      iex> SMTPProtocol.parse_mail_path("<why spaces@gmail.com>", :mail)
      {:error, "Invalid mail path"}

      iex> SMTPProtocol.parse_mail_path("<not an email>", :mail)
      {:error, "Invalid mail path"}

  Empty email addresses are used to notify sender of delivery failure:

      iex> SMTPProtocol.parse_mail_path("<>", :mail)
      {:ok, :null}

  but can't be a recipient of the email:

      iex> SMTPProtocol.parse_mail_path("<>", :rcpt)
      {:error, "Forward path can't be empty"}

  Postmaster is of course a special mailbox that we must support:

      iex> SMTPProtocol.parse_mail_path("<Postmaster>", :rcpt)
      {:ok, :postmaster}

      iex> SMTPProtocol.parse_mail_path("<Postmaster>", :mail)
      {:error, "Postmaster can't be the reverse-path"}
  """
  @spec parse_mail_path(String.t(), :mail | :rcpt) ::
          {:ok, mail_path()} | {:error, String.t()}
  def parse_mail_path(path, side) do
    # TODO(indutny): parse it properly sometime
    cond do
      path =~ ~r/^<postmaster(@.*)?>$/i ->
        case side do
          :mail -> {:error, "Postmaster can't be the reverse-path"}
          :rcpt -> {:ok, :postmaster}
        end

      path == "<>" ->
        case side do
          :mail ->
            {:ok, :null}

          :rcpt ->
            {:error, "Forward path can't be empty"}
        end

      true ->
        case Regex.run(~r/^<(.*:)?([^@\s:]+@[^@\s:]+)>$/, path) do
          nil ->
            {:error, "Invalid mail path"}

          [_, _, mailbox] ->
            {:ok, mailbox}
        end
    end
  end

  @doc ~S"""
  Parses the given mail params.

  ## Examples

      iex> SMTPProtocol.parse_mail_params("", :mail)
      {:ok, %{}}

  SIZE extension parameter would be automatically parsed from `mail-parameters`

      iex> SMTPProtocol.parse_mail_params("SIZE=123", :mail)
      {:ok, %{:size => 123}}

      iex> SMTPProtocol.parse_mail_params("SIZE=a", :mail)
      {:error, "Invalid value of SIZE parameter"}

  but not for `rcpt-parameters`:

      iex> SMTPProtocol.parse_mail_params("SIZE=a", :rcpt)
      {:error, :unknown_param}

  and duplicate values wouldn't be allowed:

      iex> SMTPProtocol.parse_mail_params("SIZE=2 SIZE=3", :mail)
      {:error, "Duplicate parameter"}

  just as unknown or incorrect parameters:

      iex> SMTPProtocol.parse_mail_params("A=42", :mail)
      {:error, :unknown_param}

      iex> SMTPProtocol.parse_mail_params("B", :mail)
      {:error, "Invalid mail parameter"}
  """
  @spec parse_mail_params(String.t(), :mail | :rcpt) ::
          {:ok, map()} | {:error, String.t() | :unknown_param}
  def parse_mail_params(params, side) do
    params
    # XXX(indutny): this is too lenient
    |> String.split(" ", trim: true)
    |> Enum.reduce({:ok, %{}}, fn part, acc ->
      with {:ok, map} <- acc do
        case String.split(part, "=", parts: 2) do
          [key, value] ->
            insert_mail_param(side, map, String.upcase(key, :ascii), value)

          _ ->
            {:error, "Invalid mail parameter"}
        end
      end
    end)
  end

  @doc """
  Parses xtext encoding.

  ## Examples

      iex> SMTPProtocol.parse_xtext("test")
      {:ok, "test"}

      iex> SMTPProtocol.parse_xtext("A+2BB")
      {:ok, "A+B"}

      iex> SMTPProtocol.parse_xtext("=")
      {:error, "Invalid xtext"}
  """
  @spec parse_xtext(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_xtext(value) do
    pattern = ~r/^([\x21-\x2a\x2c-\x3c\x3e-\x7f]|\+[0-9A-F]{2})*$/

    if Regex.match?(pattern, value) do
      {:ok,
       Regex.replace(~r/\+([0-9A-F]{2})/, value, fn _, hex ->
         hex = String.to_integer(hex, 16)
         <<hex>>
       end)}
    else
      {:error, "Invalid xtext"}
    end
  end

  #
  # Private helpers
  #

  defp insert_mail_param(side, map, key, value) do
    with {:ok, key, value} <- parse_mail_param(side, key, value) do
      if Map.has_key?(map, key) do
        {:error, "Duplicate parameter"}
      else
        {:ok, Map.put(map, key, value)}
      end
    end
  end

  defp parse_mail_param(:mail, "SIZE", value) do
    case Integer.parse(value) do
      {size, ""} -> {:ok, :size, size}
      _ -> {:error, "Invalid value of SIZE parameter"}
    end
  end

  defp parse_mail_param(_, "ALT-ADDRESS", value) do
    with {:ok, mailbox} <- parse_xtext(value) do
      {:ok, :alt_address, mailbox}
    end
  end

  defp parse_mail_param(:mail, "BODY", value) do
    case value do
      "7BIT" -> {:ok, :body, :normal}
      "8BITMIME" -> {:ok, :body, :mime}
      _ -> {:error, "Invalid value of BODY parameter"}
    end
  end

  defp parse_mail_param(_, _, _) do
    {:error, :unknown_param}
  end
end
