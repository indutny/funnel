defmodule Funnel.Repo.Migrations.CreateAllowList do
  use Ecto.Migration

  def change do
    create table("allow_list") do
      add :user, :string
      add :domain, :string
      add :created_at, :utc_datetime
    end
  end
end
