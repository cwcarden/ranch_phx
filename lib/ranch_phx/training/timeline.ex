defmodule RanchPhx.Training.Timeline do
  @moduledoc """
  The training timeline for a book: each program stage placed on the calendar by
  the horse's foaling date, where today falls, and day counts from logged
  sessions (days saddled, ground driven, ridden) plus a weekly breakdown.

  Everything here is plain data; the card component turns it into SVG.
  """

  # Stage colors run cool to warm as the program moves from handling to showing.
  @stage_colors ~w(#94a3b8 #0ea5e9 #14b8a6 #22c55e #eab308 #f97316 #ef4444 #a855f7 #ec4899)

  # A logged day counts in its "highest" category: riding beats driving beats
  # saddling beats ground work.
  @categories [
    {:ground, "Ground", "#94a3b8"},
    {:saddled, "Saddled", "#14b8a6"},
    {:driving, "Driving", "#f59e0b"},
    {:riding, "Riding", "#7c3aed"}
  ]

  @weeks 12
  @months_after_last_stage 6

  def categories, do: @categories

  def category_color(cat) do
    {_, _, color} = List.keyfind(@categories, cat, 0)
    color
  end

  @doc """
  `days` is a list of `%{date: Date, slugs: MapSet, minutes: integer}`, one per
  logged day (see `Training.logged_days/1`). `current` is the book's current
  stage (from `Training.progress/2`), which may be pinned ahead of his age.
  """
  def build(book, days, current, %Date{} = today) do
    foaled = book.horse.foaled_on
    past = Enum.filter(days, &(Date.compare(&1.date, today) != :gt))
    spans = book.program.stages |> spans(foaled) |> Enum.map(&put_logged(&1, past))
    current_span = current && Enum.find(spans, &(&1.stage.id == current.id))

    %{
      foaled_on: foaled,
      spans: spans,
      current: current_span,
      range: range(spans, foaled),
      window: {Date.add(today, -45), Date.add(today, 215)},
      goals: dated_goals(book),
      days: Enum.map(past, &Map.put(&1, :category, category(&1.slugs))),
      stats: stats(past, current_span, book, today),
      weeks: weeks(past, today)
    }
  end

  # ── Stages on the calendar ──────────────────────────────────────────────────

  defp spans(_stages, nil), do: []

  defp spans(stages, foaled) do
    stages = Enum.sort_by(stages, &{&1.from_age_months, &1.position})
    starts = Enum.map(stages, &add_months(foaled, &1.from_age_months))
    last_stop = add_months(foaled, List.last(stages).from_age_months + @months_after_last_stage)
    stops = tl(starts) ++ [last_stop]

    [stages, starts, stops]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.map(fn {{stage, start, stop}, i} ->
      %{
        stage: stage,
        index: i,
        color: Enum.at(@stage_colors, rem(i, length(@stage_colors))),
        start: start,
        stop: stop
      }
    end)
  end

  # Days logged while the horse was in this stage's age window.
  defp put_logged(span, days) do
    count =
      Enum.count(days, fn d ->
        Date.compare(d.date, span.start) != :lt and Date.compare(d.date, span.stop) == :lt
      end)

    Map.put(span, :logged, count)
  end

  defp range([], _foaled), do: nil
  defp range(spans, foaled), do: {foaled, List.last(spans).stop}

  defp dated_goals(%{goals: goals}) when is_list(goals) do
    goals
    |> Enum.filter(&(&1.status in ["active", "done"] and &1.target_date != nil))
    |> Enum.sort_by(&Date.to_gregorian_days(&1.target_date))
  end

  defp dated_goals(_book), do: []

  # ── Counts ──────────────────────────────────────────────────────────────────

  defp stats(days, span, book, today) do
    {in_stage, tracked_in_stage} =
      case span do
        nil ->
          {nil, nil}

        %{start: start, stop: stop} ->
          from = latest(start, book.started_on)

          if Date.compare(from, today) == :gt do
            {nil, 0}
          else
            tracked =
              Enum.count(days, fn d ->
                Date.compare(d.date, from) != :lt and Date.compare(d.date, stop) == :lt
              end)

            {Date.diff(today, from) + 1, tracked}
          end
      end

    %{
      days_in_stage: in_stage,
      tracked_in_stage: tracked_in_stage,
      saddled: Enum.count(days, &has_any?(&1, ~w(saddling riding))),
      driving: Enum.count(days, &has_any?(&1, ~w(ground_driving))),
      riding: Enum.count(days, &has_any?(&1, ~w(riding))),
      total_days: length(days),
      total_minutes: days |> Enum.map(&(&1.minutes || 0)) |> Enum.sum()
    }
  end

  defp has_any?(%{slugs: slugs}, wanted), do: Enum.any?(wanted, &MapSet.member?(slugs, &1))

  def category(slugs) do
    cond do
      MapSet.member?(slugs, "riding") -> :riding
      MapSet.member?(slugs, "ground_driving") -> :driving
      MapSet.member?(slugs, "saddling") -> :saddled
      true -> :ground
    end
  end

  # Logged days per week, by category, for the last @weeks weeks (Monday starts).
  defp weeks(days, today) do
    this_week = Date.beginning_of_week(today)

    for back <- (@weeks - 1)..0//-1 do
      from = Date.add(this_week, -7 * back)
      to = Date.add(from, 6)

      in_week =
        Enum.filter(days, fn d ->
          Date.compare(d.date, from) != :lt and Date.compare(d.date, to) != :gt
        end)

      counts =
        Map.new(@categories, fn {cat, _, _} ->
          {cat, Enum.count(in_week, &(category(&1.slugs) == cat))}
        end)

      %{from: from, counts: counts, total: length(in_week)}
    end
  end

  # ── Dates ───────────────────────────────────────────────────────────────────

  @doc "`date` moved by whole months, clamped to the end of shorter months."
  def add_months(%Date{year: y, month: m, day: d}, months) do
    total = y * 12 + (m - 1) + months
    year = div(total, 12)
    month = rem(total, 12) + 1
    Date.new!(year, month, min(d, Calendar.ISO.days_in_month(year, month)))
  end

  defp latest(a, nil), do: a
  defp latest(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
end
