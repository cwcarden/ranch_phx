defmodule RanchPhx.Repo.Migrations.AddThreadToCoachMessages do
  use Ecto.Migration

  # Follow-up questions point at the first message of their conversation.
  def change do
    alter table(:training_coach_messages) do
      add :thread_id, references(:training_coach_messages, on_delete: :delete_all)
    end

    create index(:training_coach_messages, [:thread_id])
  end
end
