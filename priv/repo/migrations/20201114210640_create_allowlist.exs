defmodule Funnel.Repo.Migrations.CreateAllowlist do
  use Ecto.Migration

  def change do
    create table("allowlist") do
      add :user, :string
      add :domain, :string
      add :created_at, :utc_datetime
    end
  end
end
