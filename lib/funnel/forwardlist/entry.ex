defmodule Funnel.ForwardList.Entry do
  use Ecto.Schema

  schema "forwardlist" do
    field :from, :string
    field :to, :string
    field :created_at, :utc_datetime
  end
end
