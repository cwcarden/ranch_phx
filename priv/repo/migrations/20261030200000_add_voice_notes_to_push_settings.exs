defmodule RanchPhx.Repo.Migrations.AddVoiceNotesToPushSettings do
  use Ecto.Migration

  def change do
    alter table(:push_settings) do
      add :voice_notes, :boolean, default: true, null: false
    end
  end
end
