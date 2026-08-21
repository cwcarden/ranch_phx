defmodule RanchPhx.Repo.Migrations.EnhanceTimelineEvents do
  use Ecto.Migration

  def change do
    alter table(:timeline_events) do
      add :event_time,  :time
      add :photo_urls,  {:array, :string}, default: []
    end
  end
end
