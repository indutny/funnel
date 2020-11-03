defmodule SMTPProtocol do
  @moduledoc """
  SMTP protocol helpers.
  """

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
  def parse_mail_path(path) do
    case Regex.run(~r/<(.*:)?([^:]+)>/, path) do
      nil -> {:error, "Invalid mail path"}
      [_, _, mailbox] -> {:ok, mailbox}
    end
  end

  @doc ~S"""
  Parses the given mail params.

  ## Examples

      iex> SMTPProtocol.parse_mail_params([])
      {:ok, %{}}

      iex> SMTPProtocol.parse_mail_params(["SIZE=123"])
      {:ok, %{:size => 123}}

      iex> SMTPProtocol.parse_mail_params(["A=42"])
      {:error, "Unknown mail parameter"}

      iex> SMTPProtocol.parse_mail_params(["B"])
      {:error, "Invalid mail parameter"}
  """
  def parse_mail_params(params) do
    params
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
        {:ok, Map.put(map, key, value)}

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
