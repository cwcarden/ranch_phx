defmodule RanchPhx.Repo.Migrations.CreatePush do
  use Ecto.Migration

  # Phone notifications: each device that turned them on, the app's signing keys,
  # and what's already been sent (so a reminder goes out once).
  def change do
    create table(:push_subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
      add :device, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_subscriptions, [:endpoint])

    create table(:push_keys) do
      add :public_key, :text, null: false
      add :private_key, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:push_sent) do
      add :key, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:push_sent, [:key])
  end
end
