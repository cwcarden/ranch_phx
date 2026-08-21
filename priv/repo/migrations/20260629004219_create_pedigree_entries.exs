defmodule RanchPhx.Repo.Migrations.CreatePedigreeEntries do
  use Ecto.Migration

  def change do
    create table(:pedigree_entries) do
      add :animal_id,           references(:animals, on_delete: :delete_all), null: false
      add :slot,                :string, size: 6, null: false  # e.g. "S", "DS", "SSDDS"
      add :name,                :string, null: false
      add :registration_number, :string
      add :breed,               :string
      add :birth_year,          :integer
      add :color,               :string
      add :sex,                 :string
      add :notes,               :text

      timestamps()
    end

    create unique_index(:pedigree_entries, [:animal_id, :slot])
    create index(:pedigree_entries, [:animal_id])
  end
end
