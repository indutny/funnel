defmodule FunnelSMTP do
  @moduledoc """
  Abstract SMTP protocol implementation/tools.
  """

  @type reverse_params :: map()
  @type forward_params :: map()
  @type mail_path :: :null | :postmaster | String.t()
  @type reverse_path :: :null | String.t()
  @type forward_path :: :postmaster | String.t()

  @type command_kind ::
          :helo | :ehlo | :mail_from | :rcpt_to | :data | :rset | :noop | :quit | :vrfy | :help
  @type command_extra :: String.t()
  @type command_trailing :: :crlf | :lf
  @type command :: {command_kind(), command_extra(), command_trailing()}

  @type response :: {non_neg_integer(), String.t(), :not_last | :last}

  @type extension ::
          :mime8bit
          | :starttls
          | {:size, non_neg_integer() | :unlimited | :unspecified}
          | {:unknown, String.t()}

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

  @path_re FunnelSMTP.Address.compile()
  @months {
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
  }

  @doc ~S"""
  Parses the command sent by client.

  ## Examples

      iex> FunnelSMTP.parse_command("EHLO domain\r\n")
      {:ehlo, "domain", :crlf}

      iex> FunnelSMTP.parse_command("MAIL FROM:<a@b.com> A=1 B=2\r\n")
      {:mail_from, "<a@b.com> A=1 B=2", :crlf}

      iex> FunnelSMTP.parse_command("RCPT TO:<a@b.com> A=1 B=2\r\n")
      {:rcpt_to, "<a@b.com> A=1 B=2", :crlf}

      iex> FunnelSMTP.parse_command("DATA\r\n")
      {:data, "", :crlf}

  NOTE that for commands ending with "\n" it returns different trailing string

      iex> FunnelSMTP.parse_command("DATA\n")
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
  Parses the response sent back by server.

  ## Examples

      iex> FunnelSMTP.parse_response("250\r\n")
      {:ok, {250, "", :last}}

      iex> FunnelSMTP.parse_response("250 OK\r\n")
      {:ok, {250, "OK", :last}}

      iex> FunnelSMTP.parse_response("250-8BITMIME\r\n")
      {:ok, {250, "8BITMIME", :not_last}}

      iex> FunnelSMTP.parse_response("not response\r\n")
      {:error, "Invalid response line"}
  """
  @spec parse_response(String.t()) :: {:ok, response()} | {:error, String.t()}
  def parse_response(line) do
    case Regex.run(~r/^([2-5]\d\d)?(?:([-\s])\s*(.*?))?(?:\r\n|\n)$/, line) do
      nil ->
        {:error, "Invalid response line"}

      [_, code, extra, message] ->
        last =
          case extra do
            "-" -> :not_last
            _ -> :last
          end

        {:ok, {String.to_integer(code), message, last}}
    end
  end

  @doc """
  Parse extensions from server's response to EHLO.

  ## Examples

      iex> FunnelSMTP.parse_extension("8BITMIME")
      :mime8bit

      iex> FunnelSMTP.parse_extension("SIZE")
      {:size, :unspecified}

      iex> FunnelSMTP.parse_extension("SIZE 100")
      {:size, 100}

      iex> FunnelSMTP.parse_extension("SIZE 0")
      {:size, :unlimited}

      iex> FunnelSMTP.parse_extension("STARTTLS")
      :starttls

      iex> FunnelSMTP.parse_extension("BOO")
      {:unknown, "BOO"}

      iex> FunnelSMTP.parse_extension("SIZE -100")
      {:error, "Invalid parameter of SIZE extension"}
  """
  @spec parse_extension(String.t()) :: extension() | {:error, String.t()}
  def parse_extension(ext) do
    ext
    |> String.upcase()
    |> String.split()
    |> parse_extension_parts()
  end

  @spec parse_extension_parts([String.t()]) ::
          extension() | {:error, String.t()}
  defp parse_extension_parts(["8BITMIME" | _]) do
    :mime8bit
  end

  defp parse_extension_parts(["SIZE"]) do
    {:size, :unspecified}
  end

  defp parse_extension_parts(["SIZE", param | _]) do
    case Integer.parse(param) do
      {limit, ""} ->
        cond do
          limit > 0 -> {:size, limit}
          limit == 0 -> {:size, :unlimited}
          true -> {:error, "Invalid parameter of SIZE extension"}
        end

      _ ->
        {:error, "Invalid parameter of SIZE extension"}
    end
  end

  defp parse_extension_parts(["STARTTLS" | _]) do
    :starttls
  end

  defp parse_extension_parts([name | _]) do
    {:unknown, name}
  end

  @doc ~S"""
  Parses mail and params from a single string.

  ## Examples

      iex> FunnelSMTP.parse_mail_and_params("<a@b.com> SIZE=10", :mail)
      {:ok, "a@b.com", %{size: 10}}

      iex> FunnelSMTP.parse_mail_and_params("not an email", :rcpt)
      {:error, "Invalid mail path"}
  """
  def parse_mail_and_params(str, side) do
    {path, params} =
      case String.split(str, " ", parts: 2) do
        [path] -> {path, ""}
        [path, params] -> {path, params}
      end

    with {:ok, mailbox} <- FunnelSMTP.parse_mail_path(path, side),
         {:ok, params} <- FunnelSMTP.parse_mail_params(params, side) do
      {:ok, mailbox, params}
    end
  end

  @doc ~S"""
  Parses the given mail path.

  ## Examples

  Usual email addresses:

      iex> FunnelSMTP.parse_mail_path("<hello@world.com>", :mail)
      {:ok, "hello@world.com"}

  Deprecated but supported source path part of the address:

      iex> FunnelSMTP.parse_mail_path("<@b,@c:hello@world.com>", :mail)
      {:ok, "hello@world.com"}

      iex> FunnelSMTP.parse_mail_path("<why spaces@gmail.com>", :mail)
      {:error, "Invalid mail path"}

      iex> FunnelSMTP.parse_mail_path("<not an email>", :mail)
      {:error, "Invalid mail path"}

      iex> FunnelSMTP.parse_mail_path("<\"quoted\"@mail.com>", :mail)
      {:error, "Invalid mail path. Quoted strings are not supported"}

  Empty email addresses are used to notify sender of delivery failure:

      iex> FunnelSMTP.parse_mail_path("<>", :mail)
      {:ok, :null}

  but can't be a recipient of the email:

      iex> FunnelSMTP.parse_mail_path("<>", :rcpt)
      {:error, "Forward path can't be empty"}

  Postmaster is of course a special mailbox that we must support:

      iex> FunnelSMTP.parse_mail_path("<Postmaster>", :rcpt)
      {:ok, :postmaster}

      iex> FunnelSMTP.parse_mail_path("<Postmaster>", :mail)
      {:error, "Postmaster can't be the reverse-path"}
  """
  @spec parse_mail_path(String.t(), :mail | :rcpt) ::
          {:ok, mail_path()} | {:error, String.t()}
  def parse_mail_path(path, side) do
    cond do
      path =~ ~r/^<postmaster>$/i ->
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
        case Regex.named_captures(@path_re, path) do
          nil ->
            {:error, "Invalid mail path"}

          %{"quoted_string" => qs} when qs != "" ->
            {:error, "Invalid mail path. Quoted strings are not supported"}

          %{"mailbox" => mailbox} ->
            {:ok, mailbox}
        end
    end
  end

  @doc ~S"""
  Parses the given mail params.

  ## Examples

      iex> FunnelSMTP.parse_mail_params("", :mail)
      {:ok, %{}}

  SIZE extension parameter would be automatically parsed from `mail-parameters`

      iex> FunnelSMTP.parse_mail_params("SIZE=123", :mail)
      {:ok, %{:size => 123}}

      iex> FunnelSMTP.parse_mail_params("SIZE=a", :mail)
      {:error, "Invalid value of SIZE parameter"}

  but not for `rcpt-parameters`:

      iex> FunnelSMTP.parse_mail_params("SIZE=a", :rcpt)
      {:error, :unknown_param}

  and duplicate values wouldn't be allowed:

      iex> FunnelSMTP.parse_mail_params("SIZE=2 SIZE=3", :mail)
      {:error, "Duplicate parameter"}

  just as unknown or incorrect parameters:

      iex> FunnelSMTP.parse_mail_params("A=42", :mail)
      {:error, :unknown_param}

      iex> FunnelSMTP.parse_mail_params("B", :mail)
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

      iex> FunnelSMTP.parse_xtext("test")
      {:ok, "test"}

      iex> FunnelSMTP.parse_xtext("A+2BB")
      {:ok, "A+B"}

      iex> FunnelSMTP.parse_xtext("=")
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

  @doc """
  Formats datetime for `Received:` header

  ## Examples

      iex> FunnelSMTP.format_date(~U[1984-02-16 07:06:40Z])
      "16 Feb 1984 07:06:40 +0000"

  """
  @spec format_date(DateTime.t()) :: String.t()
  def format_date(date) do
    time =
      Enum.join(
        [
          two_digit(date.hour),
          two_digit(date.minute),
          two_digit(date.second)
        ],
        ":"
      )

    # TODO(indutny): be nice an give real timezone
    zone = "+0000"

    Enum.join(
      [
        date.day,
        elem(@months, date.month - 1),
        date.year,
        time,
        zone
      ],
      " "
    )
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

  defp two_digit(n) when n < 10 do
    "0" <> Integer.to_string(n)
  end

  defp two_digit(n) do
    Integer.to_string(n)
  end
end
