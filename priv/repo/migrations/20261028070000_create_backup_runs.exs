defmodule RanchPhx.Repo.Migrations.CreateBackupRuns do
  use Ecto.Migration

  # One row per off-site backup to Cloudflare R2: what was copied and whether it worked.
  def change do
    create table(:backup_runs) do
      add :trigger, :string, null: false, default: "nightly"
      add :status, :string, null: false, default: "running"
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :db_bytes, :bigint
      add :files_uploaded, :integer, null: false, default: 0
      add :bytes_uploaded, :bigint, null: false, default: 0
      add :remote_files, :integer
      add :remote_bytes, :bigint
      add :error, :text
    end

    create index(:backup_runs, [:started_at])
  end
end
