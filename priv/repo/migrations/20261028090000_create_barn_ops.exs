defmodule RanchPhx.Repo.Migrations.CreateBarnOps do
  use Ecto.Migration

  # Things added offline in Barn mode, by the id the iPad gave them: each is applied
  # once, however many times the iPad retries sending it.
  def change do
    create table(:barn_ops) do
      add :client_id, :string, null: false
      add :kind, :string, null: false
      add :result, :map, default: %{}, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:barn_ops, [:client_id])
  end
end
