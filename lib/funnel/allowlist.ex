defmodule AllowList.Entry do
  use Ecto.Schema

  schema "allowlist" do
    field :user, :string
    field :domain, :string
    field :created_at, :utc_datetime
  end
end
