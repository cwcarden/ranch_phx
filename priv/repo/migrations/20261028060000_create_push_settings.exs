defmodule RanchPhx.Repo.Migrations.CreatePushSettings do
  use Ecto.Migration

  # Each person's notification choices: when, what, and which animals.
  def change do
    create table(:push_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :morning_on, :boolean, default: true, null: false
      add :morning_hour, :integer, default: 7, null: false
      add :evening_on, :boolean, default: true, null: false
      add :evening_hour, :integer, default: 18, null: false
      add :doses, :boolean, default: true, null: false
      add :care, :boolean, default: true, null: false
      add :care_days_ahead, :integer, default: 1, null: false
      add :overdue, :boolean, default: true, null: false
      add :muted_animal_ids, {:array, :integer}, default: [], null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_settings, [:user_id])
  end
end
