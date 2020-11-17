defmodule Funnel.Repo.Migrations.CreateForwardlist do
  use Ecto.Migration

  def change do
    create table("forwardlist") do
      add :from, :string
      add :to, :string
      add :created_at, :utc_datetime
    end
  end
end
