defmodule RanchPhx.Training do
  @moduledoc """
  Training books: each horse in training follows a program of age-based stages,
  and every session is logged against the horse's book.
  """
  import Ecto.Query
  alias RanchPhx.Repo
  alias RanchPhx.Animals.Animal

  alias RanchPhx.Training.{
    Activity,
    Book,
    Goal,
    Horse,
    Issue,
    Program,
    Routine,
    Session,
    SessionActivity,
    SessionIssue,
    SessionPhoto,
    Stage,
    Tag
  }

  # ── Dates ───────────────────────────────────────────────────────────────────

  @doc """
  Today's date for the person at the barn. `offset_minutes` is the browser's
  `Date#getTimezoneOffset()` (minutes behind UTC, e.g. 300 for US Central daylight time).
  """
  def today(offset_minutes \\ nil)

  def today(offset) when is_integer(offset),
    do: DateTime.utc_now() |> DateTime.add(-offset * 60) |> DateTime.to_date()

  def today(_), do: Date.utc_today()

  @doc "Whole months between foaling and `date`."
  def age_in_months(nil, _date), do: nil

  def age_in_months(%Date{} = birth, %Date{} = date) do
    months = (date.year - birth.year) * 12 + (date.month - birth.month)
    months = if date.day < birth.day, do: months - 1, else: months
    max(months, 0)
  end

  def age_label(nil), do: "age unknown"
  def age_label(months) when months < 24, do: "#{months} months"

  def age_label(months) do
    case rem(months, 12) do
      0 -> "#{div(months, 12)} years"
      m -> "#{div(months, 12)} yrs #{m} mo"
    end
  end

  # ── Programs ────────────────────────────────────────────────────────────────

  def list_programs do
    Repo.all(from p in Program, order_by: p.name, preload: :stages)
  end

  # ── Books ───────────────────────────────────────────────────────────────────

  def list_active_books do
    Repo.all(
      from b in Book,
        join: h in assoc(b, :horse),
        where: b.status == "active",
        order_by: h.name,
        preload: [horse: h, program: :stages, goals: []]
    )
  end

  def get_book!(id) do
    Book
    |> Repo.get!(id)
    |> Repo.preload([:horse, :goals, program: :stages])
  end

  def active_book_for_animal(animal_id) do
    Repo.one(
      from b in Book,
        join: h in assoc(b, :horse),
        where: h.animal_id == ^animal_id and b.status == "active"
    )
  end

  def change_book(%Book{} = book, attrs \\ %{}), do: Book.changeset(book, attrs)

  @doc """
  Start a book. `horse_attrs` either names a ranch animal (`"animal_id"`), whose
  training profile is reused or created from the ranch record, or describes an
  outside horse. Returns `{:ok, book}` or `{:error, :horse | :book, changeset}`.
  """
  def start_book(horse_attrs, book_attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:horse, fn _repo, _ -> find_or_create_horse(horse_attrs) end)
    |> Ecto.Multi.run(:book, fn _repo, %{horse: horse} ->
      create_book(Map.put(book_attrs, "horse_id", horse.id))
    end)
    |> Ecto.Multi.run(:goal, fn _repo, %{book: book} ->
      case String.trim(book_attrs["goal"] || "") do
        "" -> {:ok, nil}
        title -> create_goal(book, %{"title" => title, "target_date" => book_attrs["goal_date"]})
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{book: book}} -> {:ok, book}
      {:error, step, changeset, _} -> {:error, step, changeset}
    end
  end

  defp find_or_create_horse(%{"animal_id" => id}) when id not in [nil, ""] do
    case Repo.get_by(Horse, animal_id: id) do
      %Horse{} = horse ->
        {:ok, horse}

      nil ->
        animal = Repo.get!(Animal, id)

        create_horse(%{
          animal_id: animal.id,
          name: animal.name,
          foaled_on: animal.birth_date,
          sex: animal.sex,
          breed: animal.breed,
          color: animal.color,
          owner: animal.owner
        })
        |> case do
          {:ok, horse} ->
            {:ok, horse |> Horse.photo_changeset(animal.cover_photo_url) |> Repo.update!()}

          error ->
            error
        end
    end
  end

  defp find_or_create_horse(attrs), do: create_horse(Map.delete(attrs, "animal_id"))

  defp create_book(attrs) do
    %Book{} |> Book.changeset(attrs) |> Repo.insert()
  end

  @doc "Active ranch horses that aren't in an open training book."
  def ranch_horses_without_book do
    open =
      from b in Book,
        join: h in assoc(b, :horse),
        where: b.status == "active" and not is_nil(h.animal_id),
        select: h.animal_id

    Repo.all(
      from a in Animal,
        where: a.kind == "horse" and a.status == "active" and a.id not in subquery(open),
        order_by: a.name
    )
  end

  # ── Horses ──────────────────────────────────────────────────────────────────

  def get_horse!(id), do: Repo.get!(Horse, id)

  def change_horse(%Horse{} = horse, attrs \\ %{}), do: Horse.changeset(horse, attrs)

  def create_horse(attrs), do: %Horse{} |> Horse.changeset(attrs) |> Repo.insert()

  def update_horse(%Horse{} = horse, attrs), do: horse |> Horse.changeset(attrs) |> Repo.update()

  def set_horse_photo(%Horse{} = horse, url),
    do: horse |> Horse.photo_changeset(url) |> Repo.update()

  @doc "Pin the book to a stage (ready early / not ready yet). `nil` follows age again."
  def set_stage_override(%Book{} = book, stage_id) do
    book |> Ecto.Changeset.change(stage_override_id: stage_id) |> Repo.update()
  end

  # ── Where he is now ─────────────────────────────────────────────────────────

  @doc """
  The book's current stage on `date`: from the horse's age, unless the book is
  pinned to a stage. Returns a map with the stage, the next stage, and how far off it is.
  """
  def progress(%Book{program: %Program{stages: stages}} = book, %Date{} = date) do
    months = age_in_months(book.horse.foaled_on, date)
    by_age = stage_for_age(stages, months)
    current = Enum.find(stages, &(&1.id == book.stage_override_id)) || by_age
    next = current && Enum.find(stages, &(&1.position == current.position + 1))
    next_goal = upcoming_goal(book, date)

    %{
      age_months: months,
      stage: current,
      stage_number: current && current.position + 1,
      stage_count: length(stages),
      by_age: by_age,
      overridden?: book.stage_override_id != nil and current != nil,
      next: next,
      months_to_next: next && months && max(next.from_age_months - months, 0),
      next_goal: next_goal,
      days_to_goal: next_goal && Date.diff(next_goal.target_date, date)
    }
  end

  # The soonest active goal that has a date (goals must be preloaded).
  defp upcoming_goal(%Book{goals: goals}, date) when is_list(goals) do
    goals
    |> Enum.filter(&(&1.status == "active" and &1.target_date != nil))
    |> Enum.sort_by(
      &{Date.compare(&1.target_date, date) == :lt, Date.to_gregorian_days(&1.target_date)}
    )
    |> List.first()
  end

  defp upcoming_goal(_book, _date), do: nil

  defp stage_for_age(stages, nil), do: List.first(stages)

  defp stage_for_age(stages, months) do
    stages
    |> Enum.filter(&(&1.from_age_months <= months))
    |> List.last()
    |> Kernel.||(List.first(stages))
  end

  # ── Sessions ────────────────────────────────────────────────────────────────

  def list_sessions(book_id, limit \\ 50) do
    Repo.all(
      from s in Session,
        where: s.book_id == ^book_id,
        order_by: [desc: s.date, desc: s.inserted_at],
        limit: ^limit,
        preload: [:photos, activities: :activity, issue_marks: :issue]
    )
  end

  def get_session!(book_id, id) do
    Session
    |> Repo.get_by!(id: id, book_id: book_id)
    |> Repo.preload([:photos, activities: :activity, issue_marks: :issue])
  end

  def last_session(book_id), do: book_id |> list_sessions(1) |> List.first()

  def change_session(%Session{} = session, attrs \\ %{}), do: Session.changeset(session, attrs)

  @doc """
  Insert, or update the session with the same client_id (safe to re-send, and how
  edits are saved). `attrs["activities"]` is a list of maps with "activity_id" and
  optional "result", "side", "note"; `attrs["issues"]` is a list of maps with
  "issue_id", "progress" and optional "note". Both replace what the session had.
  """
  def save_session(attrs) do
    activities = attrs |> Map.get("activities", []) |> Enum.with_index()
    changeset = Session.changeset(%Session{}, attrs)

    activity_changesets =
      for {a, i} <- activities,
          do: SessionActivity.changeset(%SessionActivity{}, Map.put(a, "position", i))

    mark_changesets =
      for m <- Map.get(attrs, "issues", []), do: SessionIssue.changeset(%SessionIssue{}, m)

    cond do
      activities == [] ->
        {:error,
         Ecto.Changeset.add_error(
           %{changeset | action: :insert},
           :activities,
           "pick at least one"
         )}

      Enum.any?(activity_changesets, &(not &1.valid?)) ->
        {:error,
         Ecto.Changeset.add_error(
           %{changeset | action: :insert},
           :activities,
           "have an invalid result or side"
         )}

      Enum.any?(mark_changesets, &(not &1.valid?)) ->
        {:error,
         Ecto.Changeset.add_error(
           %{changeset | action: :insert},
           :working_on,
           "has an invalid better / same / worse"
         )}

      true ->
        Repo.transaction(fn ->
          session =
            case Repo.insert(changeset,
                   on_conflict: {:replace, [:date, :minutes, :tags, :note, :source, :updated_at]},
                   conflict_target: :client_id,
                   returning: true
                 ) do
              {:ok, session} -> session
              {:error, cs} -> Repo.rollback(cs)
            end

          Repo.delete_all(from sa in SessionActivity, where: sa.session_id == ^session.id)

          Repo.delete_all(from si in SessionIssue, where: si.session_id == ^session.id)

          for cs <- activity_changesets ++ mark_changesets do
            cs |> Ecto.Changeset.put_change(:session_id, session.id) |> Repo.insert!()
          end

          Repo.preload(session, [:photos, activities: :activity, issue_marks: :issue],
            force: true
          )
        end)
    end
  end

  @doc "Delete a session. Returns the URLs of its photos so the files can be removed."
  def delete_session(book_id, session_id) do
    urls =
      Repo.all(
        from p in SessionPhoto,
          join: s in assoc(p, :session),
          where: s.id == ^session_id and s.book_id == ^book_id,
          select: p.url
      )

    from(s in Session, where: s.id == ^session_id and s.book_id == ^book_id)
    |> Repo.delete_all()

    urls
  end

  # ── Session photos ──────────────────────────────────────────────────────────

  def add_session_photos(%Session{} = session, urls) do
    start =
      Repo.one(
        from p in SessionPhoto,
          where: p.session_id == ^session.id,
          select: coalesce(max(p.position), -1)
      ) + 1

    for {url, i} <- Enum.with_index(urls) do
      Repo.insert!(%SessionPhoto{session_id: session.id, url: url, position: start + i})
    end
  end

  @doc "Remove one photo from a session in this book. Returns `{:ok, url}` or `:error`."
  def delete_session_photo(book_id, photo_id) do
    photo =
      Repo.one(
        from p in SessionPhoto,
          join: s in assoc(p, :session),
          where: p.id == ^photo_id and s.book_id == ^book_id
      )

    case photo do
      nil -> :error
      p -> with {:ok, _} <- Repo.delete(p), do: {:ok, p.url}
    end
  end

  @doc "Sessions and minutes in the 7 days ending on `date`."
  def week_summary(book_id, %Date{} = date) do
    from_date = Date.add(date, -6)

    {count, minutes} =
      Repo.one(
        from s in Session,
          where: s.book_id == ^book_id and s.date >= ^from_date and s.date <= ^date,
          select: {count(s.id), coalesce(sum(s.minutes), 0)}
      )

    %{sessions: count, minutes: minutes}
  end

  @doc """
  Every day with a logged session in this book, oldest first:
  `%{date: Date, slugs: MapSet of activity slugs, minutes: total minutes}`.
  Several sessions on one day count as one day.
  """
  def logged_days(book_id) do
    from(s in Session,
      left_join: sa in SessionActivity,
      on: sa.session_id == s.id,
      left_join: a in Activity,
      on: a.id == sa.activity_id,
      where: s.book_id == ^book_id,
      select: {s.id, s.date, s.minutes, a.slug}
    )
    |> Repo.all()
    |> Enum.group_by(fn {_id, date, _min, _slug} -> date end)
    |> Enum.map(fn {date, rows} ->
      minutes =
        rows
        |> Enum.uniq_by(fn {id, _, _, _} -> id end)
        |> Enum.map(fn {_, _, min, _} -> min || 0 end)
        |> Enum.sum()

      slugs = for {_, _, _, slug} <- rows, slug != nil, into: MapSet.new(), do: slug
      %{date: date, slugs: slugs, minutes: minutes}
    end)
    |> Enum.sort_by(&Date.to_gregorian_days(&1.date))
  end

  @doc "Most recent session date per book, for the overview cards."
  def last_session_dates(book_ids) do
    Repo.all(
      from s in Session,
        where: s.book_id in ^book_ids,
        group_by: s.book_id,
        select: {s.book_id, max(s.date)}
    )
    |> Map.new()
  end

  @doc "How often each activity was used in this book over the last 90 days."
  def activity_usage(book_id, %Date{} = date) do
    since = Date.add(date, -90)

    Repo.all(
      from sa in SessionActivity,
        join: s in assoc(sa, :session),
        where: s.book_id == ^book_id and s.date >= ^since,
        group_by: sa.activity_id,
        select: {sa.activity_id, count(sa.id)}
    )
    |> Map.new()
  end

  @doc """
  Guardrail warnings for a session about to be logged in `stage`. `session` has
  `:minutes` and `:activities` (Activity structs); `week` is the week summary
  *before* this session; `gated` is every activity slug any stage of the program
  lists. Activities no stage mentions (ones you added yourself) never warn.
  """
  def guardrail_warnings(stage, session, week, gated \\ MapSet.new())
  def guardrail_warnings(nil, _session, _week, _gated), do: []

  def guardrail_warnings(%Stage{} = stage, session, week, gated) do
    minutes = session[:minutes]

    early =
      for a <- session[:activities] || [],
          MapSet.member?(gated, a.slug) and a.slug not in stage.session_types,
          do: "#{a.name} isn't part of this stage yet."

    [
      stage.max_session_minutes && is_integer(minutes) && minutes > stage.max_session_minutes &&
        "Longer than the #{stage.max_session_minutes} minutes suggested at this stage.",
      stage.max_sessions_per_week && week.sessions >= stage.max_sessions_per_week &&
        "That makes #{week.sessions + 1} sessions this week; this stage suggests #{stage.max_sessions_per_week} at most."
      | early
    ]
    |> Enum.filter(&is_binary/1)
  end

  @doc """
  What today looks like for a horse, from what's already logged (no AI involved).

  `sessions` are the book's sessions, newest first, with activities preloaded;
  `issues` are the horse's Working on items with marks preloaded (newest first).
  Returns:

    * `:days` – the last 7 days, oldest first: `%{date, minutes, worked?}`
    * `:status` – `:done` (logged today), `:rest` or `:work`
    * `:reason` – one plain sentence explaining the status
    * `:focus` – up to two open Working on items to work on, stickiest first
    * `:activities` – suggested activities (focus items' activities, then last time's),
      only ones this stage allows
    * `:minutes` – a suggested length, never over the stage's limit
  """
  def today_plan(stage, sessions, issues, gated, %Date{} = today) do
    by_day = Enum.group_by(sessions, & &1.date)

    days =
      for offset <- 6..0//-1 do
        date = Date.add(today, -offset)
        logged = Map.get(by_day, date, [])
        minutes = logged |> Enum.map(&(&1.minutes || 0)) |> Enum.sum()
        %{date: date, minutes: minutes, worked?: logged != []}
      end

    week_sessions = Enum.count(sessions, &(Date.diff(today, &1.date) in 0..6))
    max_week = stage && stage.max_sessions_per_week
    streak = days |> Enum.reverse() |> Enum.drop(1) |> Enum.take_while(& &1.worked?) |> length()
    today_sessions = Map.get(by_day, today, [])

    {status, reason} =
      cond do
        today_sessions != [] ->
          mins = today_sessions |> Enum.map(&(&1.minutes || 0)) |> Enum.sum()
          {:done, "Logged today#{if mins > 0, do: ": #{mins} min"}. Nice work."}

        max_week && week_sessions >= max_week ->
          {:rest,
           "He's had #{week_sessions} of #{max_week} sessions in the last 7 days. Give him the day off."}

        streak >= 3 ->
          {:rest, "He's worked #{streak} days in a row. A day off lets it soak in."}

        true ->
          left = max_week && max_week - week_sessions

          {:work,
           if(left,
             do:
               "#{left} #{if left == 1, do: "session", else: "sessions"} left in his 7-day limit.",
             else: "Good day for a session."
           )}
      end

    allowed? = fn a ->
      not MapSet.member?(gated, a.slug) or (stage && a.slug in stage.session_types)
    end

    focus =
      issues
      |> Enum.reject(&(&1.status == "solved"))
      |> Enum.sort_by(fn i ->
        last = i.marks |> List.first() |> then(&(&1 && &1.progress))
        rank = %{"worse" => 0, "same" => 1, nil => 2, "better" => 3}[last]
        {rank, Date.to_gregorian_days(i.opened_on)}
      end)
      |> Enum.take(2)

    last = List.first(sessions)

    activities =
      (Enum.map(focus, & &1.activity) ++
         if(last, do: Enum.map(last.activities, & &1.activity), else: []))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(allowed?)
      |> Enum.uniq_by(& &1.id)
      |> Enum.take(3)

    limit = stage && stage.max_session_minutes
    usual = last && last.minutes
    minutes = [usual || limit || 20, limit] |> Enum.reject(&is_nil/1) |> Enum.min()

    %{
      days: days,
      status: status,
      reason: reason,
      focus: focus,
      activities: activities,
      minutes: minutes
    }
  end

  def gated_activities(%Program{stages: stages}),
    do: stages |> Enum.flat_map(& &1.session_types) |> MapSet.new()

  # ── Activity and tag lists ──────────────────────────────────────────────────

  def list_activities(opts \\ []) do
    Activity
    |> where([a], ^Keyword.get(opts, :archived, false) or a.archived == false)
    |> order_by([a], asc: a.position, asc: a.id)
    |> Repo.all()
  end

  def list_tags(opts \\ []) do
    Tag
    |> where([t], ^Keyword.get(opts, :archived, false) or t.archived == false)
    |> order_by([t], asc: t.position, asc: t.id)
    |> Repo.all()
  end

  def create_activity(name), do: create_item(Activity, %{"name" => name})
  def create_tag(name, kind), do: create_item(Tag, %{"name" => name, "kind" => kind})

  defp create_item(schema, attrs) do
    name = String.trim(attrs["name"] || "")
    position = Repo.one(from x in schema, select: coalesce(max(x.position), -1)) + 1

    schema
    |> struct()
    |> schema.changeset(
      Map.merge(attrs, %{"slug" => unique_slug(schema, name), "position" => position})
    )
    |> Repo.insert()
  end

  defp unique_slug(schema, name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> then(&if(&1 == "", do: "item", else: &1))

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&if(&1 == 1, do: base, else: "#{base}_#{&1}"))
    |> Enum.find(&(not Repo.exists?(from x in schema, where: x.slug == ^&1)))
  end

  @doc "Rename, change kind, or hide/show an activity or tag. The slug never changes."
  def update_item(%schema{} = item, attrs) do
    item |> schema.changeset(Map.drop(attrs, ["slug"])) |> Repo.update()
  end

  @doc "Move an activity or tag one place up (-1) or down (1) in its list."
  def move_item(%schema{} = item, dir) when dir in [-1, 1] do
    items = Repo.all(from x in schema, order_by: [asc: x.position, asc: x.id])
    index = Enum.find_index(items, &(&1.id == item.id))
    swap = index + dir

    if swap >= 0 and swap < length(items) do
      items
      |> List.replace_at(index, Enum.at(items, swap))
      |> List.replace_at(swap, Enum.at(items, index))
      |> Enum.with_index()
      |> Enum.each(fn {x, i} ->
        if x.position != i, do: x |> Ecto.Changeset.change(position: i) |> Repo.update!()
      end)
    end

    :ok
  end

  # ── Goals ───────────────────────────────────────────────────────────────────

  def change_goal(%Goal{} = goal, attrs \\ %{}), do: Goal.changeset(goal, attrs)

  def create_goal(%Book{} = book, attrs) do
    position =
      Repo.one(
        from g in Goal, where: g.book_id == ^book.id, select: coalesce(max(g.position), -1)
      ) + 1

    %Goal{}
    |> Goal.changeset(Map.merge(attrs, %{"book_id" => book.id, "position" => position}))
    |> Repo.insert()
  end

  def get_goal!(book_id, id), do: Repo.get_by!(Goal, id: id, book_id: book_id)

  def update_goal(%Goal{} = goal, attrs), do: goal |> Goal.changeset(attrs) |> Repo.update()

  @doc "Mark a goal active, done or dropped. Done goals remember the day."
  def set_goal_status(%Goal{} = goal, status, %Date{} = date) do
    done_on = if status == "done", do: date
    update_goal(goal, %{"status" => status, "done_on" => done_on})
  end

  def delete_goal(%Goal{} = goal), do: Repo.delete(goal)

  # ── Working on ──────────────────────────────────────────────────────────────

  @doc "A horse's issues, open ones first, each with its session marks (newest first)."
  def list_issues(horse_id) do
    marks =
      from m in SessionIssue,
        join: s in assoc(m, :session),
        order_by: [desc: s.date, desc: s.id],
        preload: [session: s]

    Repo.all(
      from i in Issue,
        where: i.horse_id == ^horse_id,
        order_by: [
          asc: fragment("CASE ? WHEN 'solved' THEN 1 ELSE 0 END", i.status),
          asc: i.opened_on,
          asc: i.id
        ],
        preload: [:activity, marks: ^marks]
    )
  end

  def get_issue!(horse_id, id), do: Repo.get_by!(Issue, id: id, horse_id: horse_id)

  def change_issue(%Issue{} = issue, attrs \\ %{}), do: Issue.changeset(issue, attrs)

  def create_issue(horse_id, attrs, %Date{} = today) do
    %Issue{}
    |> Issue.changeset(
      attrs
      |> Map.put_new("opened_on", today)
      |> Map.merge(%{"horse_id" => horse_id, "status" => "open"})
    )
    |> Repo.insert()
  end

  def update_issue(%Issue{} = issue, attrs) do
    issue |> Issue.changeset(Map.drop(attrs, ["horse_id", "status"])) |> Repo.update()
  end

  @doc "Open, improving or solved. Solved issues remember the day."
  def set_issue_status(%Issue{} = issue, status, %Date{} = date) do
    solved_on = if status == "solved", do: date

    issue
    |> Issue.changeset(%{"status" => status, "solved_on" => solved_on})
    |> Repo.update()
  end

  def delete_issue(%Issue{} = issue), do: Repo.delete(issue)

  # ── Routines ────────────────────────────────────────────────────────────────

  def list_routines(horse_id) do
    Repo.all(from r in Routine, where: r.horse_id == ^horse_id, order_by: [asc: r.name])
  end

  def create_routine(attrs), do: %Routine{} |> Routine.changeset(attrs) |> Repo.insert()

  def delete_routine(horse_id, id) do
    from(r in Routine, where: r.id == ^id and r.horse_id == ^horse_id) |> Repo.delete_all()
  end
end
