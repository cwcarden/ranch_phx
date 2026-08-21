defmodule RanchPhx.Repo.Migrations.CreatePhotos do
  use Ecto.Migration

  def change do
    create table(:photos) do
      add :animal_id,  references(:animals, on_delete: :delete_all), null: false
      add :url,        :string, null: false
      add :caption,    :string
      add :tags,       {:array, :string}, default: []
      add :taken_at,   :date
      add :is_cover,   :boolean, default: false

      timestamps()
    end

    create index(:photos, [:animal_id])
    create index(:photos, [:taken_at])
  end
end
