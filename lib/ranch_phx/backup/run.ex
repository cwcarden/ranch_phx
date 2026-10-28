defmodule RanchPhx.Backup.Run do
  @moduledoc "One off-site backup: when, what was copied, and whether it worked."
  use Ecto.Schema

  schema "backup_runs" do
    field :trigger, :string, default: "nightly"
    field :status, :string, default: "running"
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :db_bytes, :integer
    field :files_uploaded, :integer, default: 0
    field :bytes_uploaded, :integer, default: 0
    field :remote_files, :integer
    field :remote_bytes, :integer
    field :error, :string
  end
end
