defmodule Funnel.Repo.Migrations.CreateForwardList do
  use Ecto.Migration

  def change do
    create table("forward_list") do
      add :from, :string
      add :to, :string
      add :created_at, :utc_datetime
    end
  end
end
