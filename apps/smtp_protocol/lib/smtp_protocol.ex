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
  Parses the given mail path.

  ## Examples

      iex> SMTPProtocol.parse_mail_path("<hello@world.com>")
      {:ok, "hello@world.com"}

      iex> SMTPProtocol.parse_mail_path("<@b, @c:hello@world.com>")
      {:ok, "hello@world.com"}

      iex> SMTPProtocol.parse_mail_path("hello")
      {:error, "Invalid mail path"}
  """
  @spec parse_mail_path(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_mail_path(path) do
    case Regex.run(~r/<(.*:)?([^:]+)>/, path) do
      nil -> {:error, "Invalid mail path"}
      [_, _, mailbox] -> {:ok, mailbox}
    end
  end

  @doc ~S"""
  Parses the given mail params.

  ## Examples

      iex> SMTPProtocol.parse_mail_params("")
      {:ok, %{}}

      iex> SMTPProtocol.parse_mail_params("SIZE=123")
      {:ok, %{:size => 123}}

      iex> SMTPProtocol.parse_mail_params("SIZE=a")
      {:error, "Invalid value of SIZE parameter"}

      iex> SMTPProtocol.parse_mail_params("SIZE=2 SIZE=3")
      {:error, "Duplicate parameter"}

      iex> SMTPProtocol.parse_mail_params("A=42")
      {:error, "Unknown mail parameter"}

      iex> SMTPProtocol.parse_mail_params("B")
      {:error, "Invalid mail parameter"}
  """
  @spec parse_mail_params(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_mail_params(params) do
    params
    # XXX(indutny): this is too lenient
    |> String.split(" ", trim: true)
    |> Enum.reduce({:ok, %{}}, fn part, acc ->
      with {:ok, map} <- acc do
        case String.split(part, "=", parts: 2) do
          [key, value] ->
            insert_mail_param(map, key, value)

          _ ->
            {:error, "Invalid mail parameter"}
        end
      end
    end)
  end

  defp insert_mail_param(map, key, value) do
    case parse_mail_param(key, value) do
      {:ok, key, value} ->
        if Map.has_key?(map, key) do
          {:error, "Duplicate parameter"}
        else
          {:ok, Map.put(map, key, value)}
        end

      err = {:error, _} ->
        err
    end
  end

  defp parse_mail_param("SIZE", value) do
    case Integer.parse(value) do
      {size, ""} -> {:ok, :size, size}
      _ -> {:error, "Invalid value of SIZE parameter"}
    end
  end

  defp parse_mail_param(_, _) do
    {:error, "Unknown mail parameter"}
  end
end
