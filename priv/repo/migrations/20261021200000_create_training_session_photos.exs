defmodule RanchPhx.Repo.Migrations.CreateTrainingSessionPhotos do
  use Ecto.Migration

  def change do
    create table(:training_session_photos) do
      add :session_id, references(:training_sessions, on_delete: :delete_all), null: false
      add :url,        :string, null: false
      add :position,   :integer, default: 0, null: false

      timestamps(updated_at: false)
    end

    create index(:training_session_photos, [:session_id])
  end
end
