defmodule RanchPhx.Training do
  @moduledoc """
  Training books: each horse in training follows a program of age-based stages,
  and every session is logged against the horse's book.
  """
  import Ecto.Query
  alias RanchPhx.Repo
  alias RanchPhx.Animals.Animal
  alias RanchPhx.Training.{Book, Program, Session, Stage}

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
        join: a in assoc(b, :animal),
        where: b.status == "active",
        order_by: a.name,
        preload: [animal: a, program: :stages]
    )
  end

  def get_book!(id) do
    Book
    |> Repo.get!(id)
    |> Repo.preload([:animal, program: :stages])
  end

  def active_book_for_animal(animal_id) do
    Repo.one(from b in Book, where: b.animal_id == ^animal_id and b.status == "active")
  end

  def change_book(%Book{} = book, attrs \\ %{}), do: Book.changeset(book, attrs)

  def create_book(attrs) do
    %Book{} |> Book.changeset(attrs) |> Repo.insert()
  end

  @doc "Active horses that don't have an open book yet."
  def horses_without_book do
    open = from b in Book, where: b.status == "active", select: b.animal_id

    Repo.all(
      from a in Animal,
        where: a.kind == "horse" and a.status == "active" and a.id not in subquery(open),
        order_by: a.name
    )
  end

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
    months = age_in_months(book.animal.birth_date, date)
    by_age = stage_for_age(stages, months)
    current = Enum.find(stages, &(&1.id == book.stage_override_id)) || by_age
    next = current && Enum.find(stages, &(&1.position == current.position + 1))

    %{
      age_months: months,
      stage: current,
      stage_number: current && current.position + 1,
      stage_count: length(stages),
      by_age: by_age,
      overridden?: book.stage_override_id != nil and current != nil,
      next: next,
      months_to_next: next && months && max(next.from_age_months - months, 0),
      days_to_goal: book.goal_date && Date.diff(book.goal_date, date)
    }
  end

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
        limit: ^limit
    )
  end

  def change_session(%Session{} = session, attrs \\ %{}), do: Session.changeset(session, attrs)

  @doc "Insert, or update the row with the same client_id (safe to re-send)."
  def save_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace, [:date, :session_type, :minutes, :tags, :note, :source, :updated_at]},
      conflict_target: :client_id,
      returning: true
    )
  end

  def delete_session(book_id, session_id) do
    from(s in Session, where: s.id == ^session_id and s.book_id == ^book_id)
    |> Repo.delete_all()
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

  @doc """
  Guardrail warnings for a session about to be logged in `stage`.
  `week` is the week summary *before* this session.
  """
  def guardrail_warnings(nil, _session, _week), do: []

  def guardrail_warnings(%Stage{} = stage, session, week) do
    minutes = session[:minutes]
    type = session[:session_type]

    [
      stage.max_session_minutes && is_integer(minutes) && minutes > stage.max_session_minutes &&
        "Longer than the #{stage.max_session_minutes} minutes suggested at this stage.",
      stage.max_sessions_per_week && week.sessions >= stage.max_sessions_per_week &&
        "That makes #{week.sessions + 1} sessions this week; this stage suggests #{stage.max_sessions_per_week} at most.",
      type && stage.session_types != [] && type not in stage.session_types &&
        "#{Session.type_label(type)} isn't part of this stage yet."
    ]
    |> Enum.filter(&is_binary/1)
  end
end
