defmodule RanchPhx.Repo.Migrations.CreateRecords do
  use Ecto.Migration

  def change do
    create table(:records) do
      add :animal_id,    references(:animals, on_delete: :delete_all), null: false
      add :record_type,  :string, null: false
      add :title,        :string, null: false
      add :description,  :text
      add :date,         :date, null: false
      add :next_due_date,:date
      add :location,     :string
      add :person,       :string
      add :cost,         :decimal, precision: 10, scale: 2
      add :tags,         {:array, :string}, default: []
      add :created_by,   :string
      add :notes,        :text

      timestamps()
    end

    create index(:records, [:animal_id])
    create index(:records, [:date])
  end
end
