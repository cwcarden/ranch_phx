defmodule RanchPhx.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, default: "viewer", null: false
    end
  end
end
