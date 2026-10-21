defmodule RanchPhx.Repo.Migrations.CreateTraining do
  use Ecto.Migration

  def up do
    create table(:training_programs) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:training_programs, [:slug])

    create table(:training_stages) do
      add :program_id, references(:training_programs, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :name, :string, null: false
      add :from_age_months, :integer, null: false
      add :summary, :text
      add :focus, {:array, :string}, default: [], null: false
      add :guardrail, :text
      add :max_session_minutes, :integer
      add :max_sessions_per_week, :integer
      add :session_types, {:array, :string}, default: [], null: false

      timestamps()
    end

    create unique_index(:training_stages, [:program_id, :position])

    create table(:training_books) do
      add :animal_id, references(:animals, on_delete: :delete_all), null: false
      add :program_id, references(:training_programs, on_delete: :restrict), null: false
      add :stage_override_id, references(:training_stages, on_delete: :nilify_all)
      add :status, :string, default: "active", null: false
      add :started_on, :date, null: false
      add :goal, :string
      add :goal_date, :date
      add :notes, :text

      timestamps()
    end

    create index(:training_books, [:animal_id])
    # One open book per horse; finished/paused books stay as history.
    create unique_index(:training_books, [:animal_id],
             where: "status = 'active'",
             name: :training_books_one_active_per_animal
           )

    create table(:training_sessions) do
      add :book_id, references(:training_books, on_delete: :delete_all), null: false
      add :client_id, :uuid, null: false
      add :date, :date, null: false
      add :session_type, :string, null: false
      add :minutes, :integer
      add :tags, {:array, :string}, default: [], null: false
      add :note, :text
      add :source, :string, default: "typed", null: false

      timestamps()
    end

    # Re-sending the same form (double tap, flaky barn signal) updates instead of duplicating.
    create unique_index(:training_sessions, [:client_id])
    create index(:training_sessions, [:book_id, :date])

    flush()

    seed_colt_start()
  end

  def down do
    drop table(:training_sessions)
    drop table(:training_books)
    drop table(:training_stages)
    drop table(:training_programs)
  end

  # Starting draft of a colt-to-cow-horse program. Ages are months from foaling.
  defp seed_colt_start do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %{rows: [[program_id]]} =
      repo().query!(
        "INSERT INTO training_programs (slug, name, description, inserted_at, updated_at)
         VALUES ($1, $2, $3, $4, $4) RETURNING id",
        [
          "colt_start_cow_horse",
          "Colt start → cow horse (hackamore)",
          "Handling and groundwork as a yearling, light backing near 2, real training at 3–4 in the hackamore. Move to the snaffle only when he shows he's ready.",
          now
        ]
      )

    ground = ~w(handling groundwork flag feet trailer ponying other)
    saddle = ground ++ ~w(saddling ground_driving)
    ride = saddle ++ ~w(riding)
    cow = ride ++ ~w(cattle)

    stages = [
      {"Handling & manners", 0, "Halter, lead, touch all over. Build trust and good manners.",
       [
         "Halter and lead quietly",
         "Pick up all four feet",
         "Stand tied for short periods",
         "Grooming and touch all over",
         "Load and unload"
       ], "Short and frequent. End on a good try.", 15, 5, ground},
      {"Yearling groundwork & desensitizing", 12,
       "Yielding, respect and confidence on the ground.",
       [
         "Lead from both sides; whoa and back on the ground",
         "Yield hindquarters and forequarters, both directions",
         "Flag, sacking out, tarp, spray bottle, clippers",
         "Stand for farrier, bath and trailer",
         "Pony off a broke horse"
       ],
       "No longeing or tight circles at speed: growth plates are still open. Work both sides evenly.",
       20, 4, ground},
      {"Saddling & ground driving", 20, "Get him used to gear before anyone gets on.",
       [
         "Blanket, surcingle, then saddle",
         "Cinch up in stages",
         "Ground drive",
         "Hackamore on the ground: give to pressure",
         "Flex both sides"
       ], "Light saddle, cinch gradually. Mostly walk and trot.", 25, 4, saddle},
      {"Backing & first rides", 24, "Light backing only, then lots of turnout.",
       [
         "Mount from both sides",
         "First rides at the walk, then trot",
         "One-rein stop",
         "Steer in the hackamore",
         "Ride outside the pen"
       ],
       "Ride about 15–20 minutes, a few days a week, then turn out. Rider weight matters at this age.",
       20, 3, ride},
      {"Foundation in the hackamore", 36, "Real training starts: soft, broke and fit.",
       [
         "Walk, trot, lope on both leads",
         "Stop, back and rate",
         "Soft face in the hackamore",
         "Ride outside and on trails",
         "See and follow cattle"
       ],
       "Build fitness gradually. Stay in the hackamore until he's soft and broke enough for the snaffle.",
       40, 5, cow},
      {"Cow work & maneuvers", 42, "Track, rate and turn a cow; build the reined work.",
       ["Track and rate a cow", "Boxing", "Fence work introduction", "Turnarounds", "Stops"],
       "Short cow sessions; quit before he's tired. Watch hocks and stifles.", 45, 5, cow},
      {"Show prep", 48, "Put it together for the show pen.",
       ["Run full patterns", "Haul to practice pens and shows", "Keep him fresh and sound"],
       "Don't drill the pattern. Plan rest days before the show.", 45, 5, cow}
    ]

    stages
    |> Enum.with_index()
    |> Enum.each(fn {{name, from, summary, focus, guardrail, max_min, max_week, types}, i} ->
      repo().query!(
        "INSERT INTO training_stages
           (program_id, position, name, from_age_months, summary, focus, guardrail,
            max_session_minutes, max_sessions_per_week, session_types, inserted_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $11)",
        [program_id, i, name, from, summary, focus, guardrail, max_min, max_week, types, now]
      )
    end)
  end
end
