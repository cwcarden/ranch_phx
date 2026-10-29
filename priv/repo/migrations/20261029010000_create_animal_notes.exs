defmodule RanchPhx.Repo.Migrations.CreateAnimalNotes do
  use Ecto.Migration

  # Handwritten note pages, per animal: the page as a picture, the pen strokes (so it
  # can be written on again later) and the words, read by the AI or typed.
  def change do
    create table(:animal_notes) do
      add :animal_id, references(:animals, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :topic, :string, null: false, default: "general"
      add :title, :string
      add :page_url, :string
      add :strokes_url, :string
      add :text, :text
      timestamps(type: :utc_datetime)
    end

    create index(:animal_notes, [:animal_id, :date])
  end
end
