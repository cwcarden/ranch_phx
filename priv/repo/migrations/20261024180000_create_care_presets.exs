defmodule RanchPhx.Repo.Migrations.CreateCarePresets do
  use Ecto.Migration

  # The quick-add buttons on an animal's Records tab, editable per kind of animal.
  def up do
    create table(:care_presets) do
      add :kind, :string, null: false
      add :label, :string, null: false
      add :record_type, :string, null: false
      add :title, :string, null: false
      add :product, :string
      add :interval_value, :integer
      add :interval_unit, :string
      add :position, :integer, default: 0, null: false

      timestamps()
    end

    create index(:care_presets, [:kind, :position])

    flush()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # {kind, label, record type, title, product, interval value, unit}
    rows = [
      {"horse", "Core EQ Innovator", "vaccination", "Core EQ Innovator (EWT, West Nile, Rabies)",
       nil, 12, "months"},
      {"horse", "Rhino / Flu", "vaccination", "Rhino/Flu vaccine", nil, 6, "months"},
      {"horse", "Strangles", "vaccination", "Strangles vaccine", nil, 12, "months"},
      {"horse", "Deworming", "deworming", "Deworming", "Ivermectin", 6, "months"},
      {"horse", "Coggins", "coggins", "Coggins test", nil, 12, "months"},
      {"horse", "Health cert", "health_cert", "Health certificate exam", nil, nil, nil},
      {"horse", "Vet exam", "vet_visit", "Veterinary exam", nil, 12, "months"},
      {"horse", "Trim", "trim", "Hoof trim", nil, 6, "weeks"},
      {"horse", "Shoes", "shoeing", "Shoeing", nil, 6, "weeks"},
      {"horse", "Dental", "dental_float", "Dental float", nil, 12, "months"},
      {"dog", "Rabies", "vaccination", "Rabies vaccine", nil, 12, "months"},
      {"dog", "DHPP", "vaccination", "DHPP vaccine", nil, 12, "months"},
      {"dog", "Bordetella", "vaccination", "Bordetella vaccine", nil, 12, "months"},
      {"dog", "Deworming", "deworming", "Deworming", nil, 3, "months"},
      {"dog", "Heartworm", "medication", "Heartworm prevention", nil, 1, "months"},
      {"dog", "Vet exam", "vet_visit", "Wellness exam", nil, 12, "months"},
      {"other", "Vaccination", "vaccination", "Vaccination", nil, 12, "months"},
      {"other", "Deworming", "deworming", "Deworming", nil, 3, "months"},
      {"other", "Vet visit", "vet_visit", "Vet visit", nil, nil, nil}
    ]

    rows
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.each(fn {_kind, list} ->
      list
      |> Enum.with_index()
      |> Enum.each(fn {{kind, label, type, title, product, value, unit}, pos} ->
        repo().insert_all("care_presets", [
          [
            kind: kind,
            label: label,
            record_type: type,
            title: title,
            product: product,
            interval_value: value,
            interval_unit: unit,
            position: pos,
            inserted_at: now,
            updated_at: now
          ]
        ])
      end)
    end)
  end

  def down, do: drop(table(:care_presets))
end
