defmodule SMTPParser do
  @moduledoc """
  SMTP helpers.
  """

  @doc ~S"""
  Parses the given path.

      iex> SMTPParser.parse_path("<hello@world.com>")
      {:ok, "hello@world.com"}

      iex> SMTPParser.parse_path("<@b, @c:hello@world.com>")
      {:ok, "hello@world.com"}

      iex> SMTPParser.parse_path("hello")
      {:error, "Invalid mailbox"}
  """
  def parse_path(path) do
    case Regex.run(~r/<(.*:)?([^:]+)>/, path) do
      nil -> {:error, "Invalid mailbox"}
      [_, _, mailbox] -> {:ok, mailbox}
    end
  end
end
