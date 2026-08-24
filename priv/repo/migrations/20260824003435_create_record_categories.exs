defmodule RanchPhx.Repo.Migrations.CreateRecordCategories do
  use Ecto.Migration

  def up do
    create table(:record_categories) do
      add :slug,       :string, null: false
      add :label,      :string, null: false
      add :color,      :string, null: false
      add :position,   :integer, default: 0, null: false
      add :is_builtin, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:record_categories, [:slug])

    flush()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows = [
      {"identification", "Identification", "#6366f1", 0},
      {"health",         "Health",         "#2563eb", 1},
      {"hoof_care",      "Hoof Care",      "#d97706", 2},
      {"training",       "Training",       "#7c3aed", 3},
      {"performance",    "Performance",    "#0891b2", 4},
      {"nutrition",      "Nutrition",      "#16a34a", 5},
      {"breeding",       "Breeding",       "#ec4899", 6},
      {"transportation", "Transportation", "#64748b", 7},
      {"media",          "Media",          "#0ea5e9", 8},
      {"journal",        "Journal",        "#78716c", 9}
    ]

    Enum.each(rows, fn {slug, label, color, pos} ->
      repo().insert_all("record_categories", [[
        slug: slug, label: label, color: color,
        position: pos, is_builtin: true,
        inserted_at: now, updated_at: now
      ]])
    end)
  end

  def down do
    drop table(:record_categories)
  end
end
