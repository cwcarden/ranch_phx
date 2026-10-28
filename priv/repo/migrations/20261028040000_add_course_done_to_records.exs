defmodule RanchPhx.Repo.Migrations.AddCourseDoneToRecords do
  use Ecto.Migration

  # Days a multi-day treatment (e.g. Panacur PowerPac, daily for 5 days) was given.
  def change do
    alter table(:records) do
      add :course_done, {:array, :date}, default: [], null: false
    end
  end
end
