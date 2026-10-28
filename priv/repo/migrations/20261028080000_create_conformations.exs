defmodule RanchPhx.Repo.Migrations.CreateConformations do
  use Ecto.Migration

  # Conformation from a side photo: of one of the ranch's horses, or of a prospect
  # being looked at (no animal, just a name and notes).
  def change do
    create table(:conformations) do
      add :animal_id, references(:animals, on_delete: :delete_all)
      add :name, :string
      add :note, :text
      add :date, :date, null: false
      add :photo_url, :string
      add :original_url, :string
      add :points, :map, default: %{}, null: false
      add :shoulder, :float
      add :hip, :float
      add :uphill, :float
      add :length_ratio, :float
      add :neck_ratio, :float
      add :thirds, {:array, :integer}
      add :ai_notes, :text
      # Questions asked about this horse and the answers: [%{"q" => ..., "a" => ...}]
      add :ai_chat, {:array, :map}, default: [], null: false
      timestamps(type: :utc_datetime)
    end

    create index(:conformations, [:animal_id])
  end
end
