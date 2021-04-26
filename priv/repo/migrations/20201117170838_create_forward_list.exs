defmodule Funnel.Repo.Migrations.CreateForwardList do
  use Ecto.Migration

  def change do
    create table("forward_list") do
      add :source, :string
      add :target, :string
      add :created_at, :utc_datetime
    end

    create unique_index("forward_list", [:source])
  end
end
