defmodule RanchPhx.Repo.Migrations.TrainingActivitiesGoalsRoutines do
  use Ecto.Migration

  # Sessions hold several activities (each with an optional result and side),
  # activity and tag lists become editable, books get a goals list, and each
  # horse can have saved routines.
  def up do
    create table(:training_activities) do
      add :slug,     :string, null: false
      add :name,     :string, null: false
      add :position, :integer, default: 0, null: false
      add :archived, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:training_activities, [:slug])

    create table(:training_tags) do
      add :slug,     :string, null: false
      add :name,     :string, null: false
      # good | problem | health — health tags show the "rest and check with your vet" note
      add :kind,     :string, default: "problem", null: false
      add :position, :integer, default: 0, null: false
      add :archived, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:training_tags, [:slug])

    create table(:training_session_activities) do
      add :session_id,  references(:training_sessions, on_delete: :delete_all), null: false
      add :activity_id, references(:training_activities, on_delete: :restrict), null: false
      add :position,    :integer, default: 0, null: false
      add :result,      :string
      add :side,        :string
      add :note,        :text
    end

    create index(:training_session_activities, [:session_id])
    create index(:training_session_activities, [:activity_id])

    create table(:training_goals) do
      add :book_id,     references(:training_books, on_delete: :delete_all), null: false
      add :title,       :string, null: false
      add :target_date, :date
      add :status,      :string, default: "active", null: false
      add :notes,       :text
      add :position,    :integer, default: 0, null: false
      add :done_on,     :date

      timestamps()
    end

    create index(:training_goals, [:book_id])

    create table(:training_routines) do
      add :horse_id,     references(:training_horses, on_delete: :delete_all), null: false
      add :name,         :string, null: false
      add :activity_ids, {:array, :bigint}, default: [], null: false
      add :minutes,      :integer
      add :tags,         {:array, :string}, default: [], null: false

      timestamps()
    end

    create index(:training_routines, [:horse_id])

    flush()

    activities = [
      {"handling", "Handling"},
      {"groundwork", "Groundwork"},
      {"flag", "Flag / sacking"},
      {"feet", "Feet"},
      {"longeing", "Longeing"},
      {"trailer", "Trailer"},
      {"ponying", "Ponying"},
      {"saddling", "Saddling"},
      {"ground_driving", "Ground driving"},
      {"riding", "Riding"},
      {"cattle", "Cattle"},
      {"other", "Other"}
    ]

    for {{slug, name}, i} <- Enum.with_index(activities) do
      execute "INSERT INTO training_activities (slug, name, position, inserted_at, updated_at)
               VALUES ('#{slug}', '#{name}', #{i}, NOW(), NOW())"
    end

    tags = [
      {"good", "Good", "good"},
      {"quiet", "Quiet", "good"},
      {"distracted", "Distracted", "problem"},
      {"spooky", "Spooky", "problem"},
      {"pushy", "Pushy", "problem"},
      {"sticky_left", "Sticky left", "problem"},
      {"sticky_right", "Sticky right", "problem"},
      {"sore", "Sore", "health"}
    ]

    for {{slug, name, kind}, i} <- Enum.with_index(tags) do
      execute "INSERT INTO training_tags (slug, name, kind, position, inserted_at, updated_at)
               VALUES ('#{slug}', '#{name}', '#{kind}', #{i}, NOW(), NOW())"
    end

    # Every existing session keeps its one activity...
    execute """
    INSERT INTO training_session_activities (session_id, activity_id, position)
    SELECT s.id, a.id, 0 FROM training_sessions s
    JOIN training_activities a ON a.slug = s.session_type
    """

    # ...plus any activity its note clearly mentions (e.g. "feet, light longeing").
    for {slug, pattern} <- [
          {"feet", "%feet%"},
          {"longeing", "%longe%"},
          {"longeing", "%lunge%"},
          {"longeing", "%lounge%"},
          {"trailer", "%trailer%"},
          {"saddling", "%saddl%"},
          {"ponying", "%pony%"}
        ] do
      execute """
      INSERT INTO training_session_activities (session_id, activity_id, position)
      SELECT s.id, a.id, 1 FROM training_sessions s, training_activities a
      WHERE a.slug = '#{slug}' AND s.note ILIKE '#{pattern}'
        AND NOT EXISTS (SELECT 1 FROM training_session_activities x
                        WHERE x.session_id = s.id AND x.activity_id = a.id)
      """
    end

    execute """
    INSERT INTO training_goals (book_id, title, target_date, inserted_at, updated_at)
    SELECT id, goal, goal_date, NOW(), NOW() FROM training_books
    WHERE goal IS NOT NULL AND goal <> ''
    """

    # Light longeing is fine from the yearling stage on.
    execute """
    UPDATE training_stages SET session_types = array_append(session_types, 'longeing')
    WHERE position >= 1 AND NOT ('longeing' = ANY(session_types))
      AND program_id = (SELECT id FROM training_programs WHERE slug = 'colt_start_cow_horse')
    """

    execute """
    UPDATE training_stages
    SET guardrail = 'Longe only lightly: big circles, mostly walk and trot, a few minutes each way. No tight circles or speed: growth plates are still open. Work both sides evenly.'
    WHERE position = 1
      AND program_id = (SELECT id FROM training_programs WHERE slug = 'colt_start_cow_horse')
    """

    alter table(:training_sessions) do
      remove :session_type
    end

    alter table(:training_books) do
      remove :goal
      remove :goal_date
    end
  end

  def down do
    alter table(:training_books) do
      add :goal, :string
      add :goal_date, :date
    end

    alter table(:training_sessions) do
      add :session_type, :string
    end

    flush()

    execute """
    UPDATE training_books b SET goal = g.title, goal_date = g.target_date
    FROM (SELECT DISTINCT ON (book_id) * FROM training_goals ORDER BY book_id, position, id) g
    WHERE g.book_id = b.id
    """

    execute """
    UPDATE training_sessions s SET session_type = a.slug
    FROM (SELECT DISTINCT ON (session_id) session_id, activity_id FROM training_session_activities
          ORDER BY session_id, position, id) sa
    JOIN training_activities a ON a.id = sa.activity_id
    WHERE sa.session_id = s.id
    """

    execute "UPDATE training_sessions SET session_type = 'other' WHERE session_type IS NULL"

    drop table(:training_routines)
    drop table(:training_goals)
    drop table(:training_session_activities)
    drop table(:training_tags)
    drop table(:training_activities)
  end
end
