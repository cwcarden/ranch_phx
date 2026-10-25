defmodule RanchPhx.Repo.Migrations.CreateVoiceNotes do
  use Ecto.Migration

  # Things said to Siri ("Ranch log"), waiting to be checked and saved as records.
  def change do
    create table(:voice_notes) do
      add :text, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :animal_id, references(:animals, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:voice_notes, [:status, :inserted_at])
  end
end
