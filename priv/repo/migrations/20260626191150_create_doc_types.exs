defmodule RanchPhx.Repo.Migrations.CreateDocTypes do
  use Ecto.Migration

  def change do
    create table(:doc_types) do
      add :name,     :string, null: false
      add :position, :integer, default: 0
      timestamps()
    end

    create unique_index(:doc_types, [:name])

    # Remove the old string-enum constraint on documents.doc_type since
    # it now references user-defined types by name
  end
end
