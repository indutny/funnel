defmodule Funnel.AllowList.Entry do
  use Ecto.Schema

  schema "allow_list" do
    field :user, :string
    field :domain, :string
    field :created_at, :utc_datetime
  end
end
