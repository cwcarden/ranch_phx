defmodule RanchPhx.Repo.Migrations.AddTaskRecordType do
  use Ecto.Migration

  # Your own daily reminders ("Soak left front", "Hand walk 10 min") that aren't
  # medicine: a journal kind, so they stay out of the health record.
  def up do
    execute """
    INSERT INTO record_types (category, slug, label, position, is_builtin, inserted_at, updated_at)
    VALUES ('journal', 'task', 'Daily task', 10, true, now(), now())
    ON CONFLICT (slug) DO NOTHING
    """
  end

  def down, do: execute("DELETE FROM record_types WHERE slug = 'task'")
end
