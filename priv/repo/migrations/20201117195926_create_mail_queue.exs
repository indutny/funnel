defmodule Funnel.Repo.Migrations.CreateMailQueue do
  use Ecto.Migration

  def change do
    create table("mail_queue") do
      add :from, :string
      add :to, :string
      add :created_at, :utc_datetime
    end
  end
end
