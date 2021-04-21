defmodule Funnel.ForwardList.Entry do
  use Ecto.Schema

  schema "forward_list" do
    field :source, :string
    field :target, :string
    field :created_at, :utc_datetime
  end
end
