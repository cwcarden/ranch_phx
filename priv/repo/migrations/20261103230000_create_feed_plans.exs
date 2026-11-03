defmodule RanchPhx.Repo.Migrations.CreateFeedPlans do
  use Ecto.Migration

  def change do
    create table(:feed_plans) do
      add :animal_id, references(:animals, on_delete: :delete_all), null: false
      add :sections, {:array, :map}, null: false, default: []
      add :share_token, :string, null: false
      add :share_on, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:feed_plans, [:animal_id])
    create unique_index(:feed_plans, [:share_token])
  end
end
