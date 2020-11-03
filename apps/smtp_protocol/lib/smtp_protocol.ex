defmodule SMTPProtocol do
  @moduledoc """
  SMTP protocol helpers.
  """

  @doc ~S"""
  Parses the handshake message.

      iex> SMTPProtocol.parse_handshake("EHLO")
      {:ok, :extended, nil}

      iex> SMTPProtocol.parse_handshake("EHLO domain")
      {:ok, :extended, "domain"}

      iex> SMTPProtocol.parse_handshake("HELO domain")
      {:ok, :legacy, "domain"}

      iex> SMTPProtocol.parse_handshake("LOHE")
      {:error, "Invalid handshake"}
  """
  @spec parse_handshake(String.t()) ::
          {:ok, :legacy | :extended, String.t() | nil}
          | {:error, String.t()}
  def parse_handshake("HELO " <> domain) do
    {:ok, :legacy, domain}
  end

  def parse_handshake("EHLO " <> domain) do
    {:ok, :extended, domain}
  end

  def parse_handshake("EHLO") do
    {:ok, :extended, nil}
  end

  def parse_handshake(_) do
    {:error, "Invalid handshake"}
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

      iex> SMTPProtocol.parse_mail_path("not an email", :mail)
      {:error, "Invalid mail path"}

  Empty email addresses are used to notify sender of delivery failure:

      iex> SMTPProtocol.parse_mail_path("<>", :mail)
      {:ok, ""}

  but can't be a recipient of the email:

      iex> SMTPProtocol.parse_mail_path("<>", :rcpt)
      {:error, "Forward path can't be empty"}

  """
  @spec parse_mail_path(String.t(), :mail | :rcpt) ::
          {:ok, String.t()} | {:error, String.t()}
  def parse_mail_path(path, side) do
    case {side, Regex.run(~r/<(.*:)?([^:]*)>/, path)} do
      {_, nil} -> {:error, "Invalid mail path"}
      {:rcpt, [_, _, ""]} -> {:error, "Forward path can't be empty"}
      {_, [_, _, mailbox]} -> {:ok, mailbox}
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
      {:error, "Unknown mail parameter"}

  and duplicate values wouldn't be allowed:

      iex> SMTPProtocol.parse_mail_params("SIZE=2 SIZE=3", :mail)
      {:error, "Duplicate parameter"}

  just as unknown or incorrect parameters:

      iex> SMTPProtocol.parse_mail_params("A=42", :mail)
      {:error, "Unknown mail parameter"}

      iex> SMTPProtocol.parse_mail_params("B", :mail)
      {:error, "Invalid mail parameter"}
  """
  @spec parse_mail_params(String.t(), :mail | :rcpt) ::
          {:ok, map()} | {:error, String.t()}
  def parse_mail_params(params, side) do
    params
    # XXX(indutny): this is too lenient
    |> String.split(" ", trim: true)
    |> Enum.reduce({:ok, %{}}, fn part, acc ->
      with {:ok, map} <- acc do
        case String.split(part, "=", parts: 2) do
          [key, value] ->
            insert_mail_param(side, map, key, value)

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
    {:error, "Unknown mail parameter"}
  end
end
