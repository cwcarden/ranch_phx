defmodule RanchPhx.Repo.Migrations.CreateTrainingCoachMessages do
  use Ecto.Migration

  # Questions asked of the Coach and its answers, kept per book.
  def change do
    create table(:training_coach_messages) do
      add :book_id,  references(:training_books, on_delete: :delete_all), null: false
      add :question, :text, null: false
      add :answer,   :text, null: false
      add :checked,  {:array, :string}, default: [], null: false
      add :model,    :string

      timestamps(updated_at: false)
    end

    create index(:training_coach_messages, [:book_id, :inserted_at])
  end
end
