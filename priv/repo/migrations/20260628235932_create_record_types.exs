defmodule RanchPhx.Repo.Migrations.CreateRecordTypes do
  use Ecto.Migration

  def up do
    create table(:record_types) do
      add :category,   :string, null: false
      add :slug,       :string, null: false
      add :label,      :string, null: false
      add :position,   :integer, default: 0, null: false
      add :is_builtin, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:record_types, [:slug])
    create index(:record_types, [:category])

    flush()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows = [
      # Identification
      {"identification", "aqha_registration",    "AQHA Registration",     0},
      {"identification", "registration_transfer", "Registration Transfer", 1},
      {"identification", "brand",                 "Brand",                 2},
      {"identification", "microchip",             "Microchip",             3},
      {"identification", "dna",                   "DNA",                   4},
      {"identification", "ownership",             "Ownership",             5},
      {"identification", "insurance",             "Insurance",             6},
      # Health
      {"health", "vaccination",  "Vaccination",        0},
      {"health", "deworming",    "Deworming",          1},
      {"health", "vet_visit",    "Veterinary Visit",   2},
      {"health", "dental_float", "Dental Float",       3},
      {"health", "medication",   "Medication",         4},
      {"health", "injury",       "Injury",             5},
      {"health", "surgery",      "Surgery",            6},
      {"health", "lab_test",     "Lab Test",           7},
      {"health", "coggins",      "Coggins",            8},
      {"health", "health_cert",  "Health Certificate", 9},
      # Hoof Care
      {"hoof_care", "trim",            "Trim",            0},
      {"hoof_care", "shoeing",         "Shoeing",         1},
      {"hoof_care", "pads",            "Pads",            2},
      {"hoof_care", "corrective_trim", "Corrective Trim", 3},
      # Training
      {"training", "groundwork",      "Groundwork",      0},
      {"training", "round_pen",       "Round Pen",       1},
      {"training", "leading",         "Leading",         2},
      {"training", "trailer",         "Trailer Loading", 3},
      {"training", "ground_tie",      "Ground Tie",      4},
      {"training", "saddling",        "Saddling",        5},
      {"training", "ground_driving",  "Ground Driving",  6},
      {"training", "arena_work",      "Arena Work",      7},
      {"training", "trail_ride",      "Trail Ride",      8},
      {"training", "tracking_cattle", "Tracking Cattle", 9},
      {"training", "roping",          "Roping",          10},
      {"training", "lesson",          "Lesson",          11},
      # Performance
      {"performance", "aqha_show",   "AQHA Show",   0},
      {"performance", "jackpot",     "Jackpot",     1},
      {"performance", "clinic",      "Clinic",      2},
      {"performance", "competition", "Competition", 3},
      {"performance", "judging",     "Judging",     4},
      {"performance", "awards",      "Awards",      5},
      # Nutrition
      {"nutrition", "feed_change",    "Feed Change",    0},
      {"nutrition", "hay_analysis",   "Hay Analysis",   1},
      {"nutrition", "supplement",     "Supplement",     2},
      {"nutrition", "weight",         "Weight",         3},
      {"nutrition", "height",         "Height",         4},
      {"nutrition", "body_condition", "Body Condition", 5},
      # Breeding
      {"breeding", "breeding",         "Breeding",         0},
      {"breeding", "pregnancy",        "Pregnancy",        1},
      {"breeding", "foaling",          "Foaling",          2},
      {"breeding", "embryo",           "Embryo",           3},
      {"breeding", "semen_collection", "Semen Collection", 4},
      # Transportation
      {"transportation", "trip",               "Trip",               0},
      {"transportation", "interstate_travel",  "Interstate Travel",  1},
      {"transportation", "travel_health_cert", "Health Certificate", 2},
      # Media
      {"media", "photo_session", "Photo Session", 0},
      {"media", "video",         "Video",         1},
      # Journal
      {"journal", "daily_note",  "Daily Note",  0},
      {"journal", "milestone",   "Milestone",   1},
      {"journal", "observation", "Observation", 2}
    ]

    Enum.each(rows, fn {cat, slug, label, pos} ->
      repo().insert_all("record_types", [[
        category: cat, slug: slug, label: label,
        position: pos, is_builtin: true,
        inserted_at: now, updated_at: now
      ]])
    end)
  end

  def down do
    drop table(:record_types)
  end
end
