defmodule RanchPhx.Animals.Insights do
  @moduledoc """
  Small facts worked out from what's already recorded, for the animal cards and the
  Overview tab: weight and how fast it's changing (from timeline weight entries and
  weight records), and the one care item that needs attention.
  """
  alias RanchPhx.Animals.CareSchedule

  # A number, optionally followed by a unit: "780 lb", "1,050 lbs", "354 kg", "780#".
  @number ~r/(\d{1,2},\d{3}|\d+(?:\.\d+)?)\s*(lbs?|pounds?|#|kgs?|kilo(?:gram)?s?)?(?![a-z0-9])/i

  @doc """
  Pounds from text like "780 lb by tape", "Weighed 1,050 lbs" or "354 kg". Without a
  unit, a number between 50 and 3,000 is taken as pounds. Nil when there's none.
  """
  def parse_weight(text) do
    matches = Regex.scan(@number, to_string(text))

    # A body weight is 50–3,000 lb; with several ("gained 15 lb, now 805 lb") the last wins.
    weights =
      for m <- matches,
          lbs = to_lbs(Enum.at(m, 1), Enum.at(m, 2)),
          lbs in 50..3000//1,
          do: {Enum.at(m, 2) not in [nil, ""], lbs}

    case Enum.filter(weights, &elem(&1, 0)) do
      [] -> weights |> List.last() |> then(&(&1 && elem(&1, 1)))
      with_unit -> with_unit |> List.last() |> elem(1)
    end
  end

  defp to_lbs(n, unit) do
    value = n |> String.replace(",", "") |> Float.parse() |> elem(0)
    value = if unit && String.downcase(unit) =~ ~r/^k/, do: value * 2.20462, else: value
    round(value)
  end

  @doc """
  Dated weights in pounds, oldest first, from timeline events of type "weight" and
  records of type "weight". One per day (the later entry wins).
  """
  def weights(events, records) do
    from_events =
      for e <- events,
          e.event_type == "weight",
          date = event_date(e),
          lbs = stored_lbs(e) || parse_weight("#{e.title} #{e.description}"),
          do: {date, lbs, e.inserted_at}

    from_records =
      for r <- records,
          r.record_type == "weight",
          lbs = parse_weight("#{r.title} #{r.description} #{r.notes}"),
          do: {r.date, lbs, r.inserted_at}

    (from_events ++ from_records)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {date, entries} ->
      {date, entries |> Enum.max_by(&elem(&1, 2), NaiveDateTime) |> elem(1)}
    end)
    |> Enum.sort_by(&Date.to_gregorian_days(elem(&1, 0)))
  end

  # Weigh-ins logged with the weight form keep the number itself.
  defp stored_lbs(%{metadata: %{"lbs" => lbs}}) when is_number(lbs), do: round(lbs)
  defp stored_lbs(_), do: nil

  @doc "How the latest weigh-in was measured (\"scale\", \"tape\", \"estimate\"), if recorded."
  def latest_method(events) do
    events
    |> Enum.filter(&(&1.event_type == "weight" and is_map(&1.metadata) and &1.metadata["method"]))
    |> Enum.max_by(&{Date.to_gregorian_days(event_date(&1)), &1.inserted_at}, fn -> nil end)
    |> then(&(&1 && &1.metadata["method"]))
  end

  defp event_date(%{event_date: %Date{} = d}), do: d
  defp event_date(%{inserted_at: %NaiveDateTime{} = t}), do: NaiveDateTime.to_date(t)
  defp event_date(_), do: nil

  @doc """
  The weight picture: latest weight, average gain per day across all weigh-ins (a
  straight-line fit, so one odd reading doesn't swing it), and the change over about
  the last month. Gains need at least two weigh-ins a week or more apart.
  """
  def weight_trend([]), do: nil

  def weight_trend(points) do
    {last_date, last_lbs} = List.last(points)
    {first_date, _} = List.first(points)
    span = Date.diff(last_date, first_date)

    month_ago =
      points
      |> Enum.filter(fn {d, _} -> Date.diff(last_date, d) >= 21 end)
      |> List.last()

    %{
      latest: last_lbs,
      date: last_date,
      count: length(points),
      per_day: if(length(points) >= 2 and span >= 7, do: slope(points)),
      month_change:
        month_ago &&
          %{lbs: last_lbs - elem(month_ago, 1), days: Date.diff(last_date, elem(month_ago, 0))},
      points: points
    }
  end

  # Least-squares slope in pounds per day.
  defp slope(points) do
    {d0, _} = hd(points)
    xy = Enum.map(points, fn {d, w} -> {Date.diff(d, d0), w} end)
    n = length(xy)
    mx = Enum.sum(Enum.map(xy, &elem(&1, 0))) / n
    my = Enum.sum(Enum.map(xy, &elem(&1, 1))) / n
    num = Enum.sum(Enum.map(xy, fn {x, y} -> (x - mx) * (y - my) end))
    den = Enum.sum(Enum.map(xy, fn {x, _} -> (x - mx) * (x - mx) end))
    if den == 0, do: nil, else: Float.round(num / den, 2)
  end

  @doc """
  The one care item worth showing: the most overdue, else the soonest due within 30
  days, else nil. `%{record, days}`.
  """
  def care_alert(records, %Date{} = today) do
    case CareSchedule.status(records, today) do
      [%{days: days} = first | _] when days <= 30 -> first
      _ -> nil
    end
  end

  @doc "Weigh-ins placed on a `w` by `h` chart: `[{x, y, date, lbs}]`, oldest first."
  def chart_points(points, w, h, pad \\ 2) when length(points) >= 2 do
    {d0, _} = hd(points)
    xs = Enum.map(points, fn {d, _} -> Date.diff(d, d0) end)
    ys = Enum.map(points, &elem(&1, 1))
    {xmax, ymin, ymax} = {max(Enum.max(xs), 1), Enum.min(ys), Enum.max(ys)}
    yr = max(ymax - ymin, 1)

    Enum.zip_with([xs, points], fn [x, {d, y}] ->
      {Float.round(pad + x / xmax * (w - 2 * pad), 1),
       Float.round(h - pad - (y - ymin) / yr * (h - 2 * pad), 1), d, y}
    end)
  end

  def chart_points(_points, _w, _h, _pad), do: []

  @doc "Points for a small inline SVG line, scaled to `w` by `h`, or nil."
  def sparkline(points, w, h) do
    case chart_points(points, w, h) do
      [] -> nil
      pts -> Enum.map_join(pts, " ", fn {x, y, _, _} -> "#{x},#{y}" end)
    end
  end
end
