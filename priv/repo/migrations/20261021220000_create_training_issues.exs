defmodule RanchPhx.Repo.Migrations.CreateTrainingIssues do
  use Ecto.Migration

  # "Working on": problems per horse, and how each session moved them.
  def change do
    create table(:training_issues) do
      add :horse_id,    references(:training_horses, on_delete: :delete_all), null: false
      add :activity_id, references(:training_activities, on_delete: :nilify_all)
      add :title,       :string, null: false
      add :side,        :string
      add :status,      :string, default: "open", null: false
      add :notes,       :text
      add :opened_on,   :date, null: false
      add :solved_on,   :date

      timestamps()
    end

    create index(:training_issues, [:horse_id])

    create table(:training_session_issues) do
      add :session_id, references(:training_sessions, on_delete: :delete_all), null: false
      add :issue_id,   references(:training_issues, on_delete: :delete_all), null: false
      add :progress,   :string, null: false
      add :note,       :text
    end

    create unique_index(:training_session_issues, [:session_id, :issue_id])
    create index(:training_session_issues, [:issue_id])
  end
end
