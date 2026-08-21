defmodule RanchPhx.Repo.Migrations.CreateTimelineEvents do
  use Ecto.Migration

  def change do
    create table(:timeline_events) do
      add :animal_id,   references(:animals, on_delete: :delete_all), null: false
      add :event_type,  :string, null: false
      add :title,       :string
      add :description, :text
      add :event_date,  :date, null: false
      add :location,    :string
      add :metadata,    :map, default: %{}

      timestamps()
    end

    create index(:timeline_events, [:animal_id])
    create index(:timeline_events, [:event_date])
    create index(:timeline_events, [:event_type])
  end
end
