defmodule RanchPhx.Repo.Migrations.AddCategoryToRecords do
  use Ecto.Migration

  def change do
    alter table(:records) do
      add :category, :string
    end
  end
end
