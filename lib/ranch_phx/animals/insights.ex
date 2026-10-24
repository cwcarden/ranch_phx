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

  # ── Height ──

  @doc """
  Inches from text like "14.2 hh", "14.2 hands", "58 in" or "58\"". Hands are written
  hands.inches (14.2 is 14 hands 2 inches = 58 in). A bare number from 8 to 19 is
  read as hands. Nil when there's none.
  """
  def parse_height(text) do
    text = String.downcase(to_string(text))

    cond do
      m = Regex.run(~r/(\d{2,3}(?:\.\d)?)\s*(?:in\b|inch|inches|")/, text) ->
        m |> Enum.at(1) |> Float.parse() |> elem(0)

      m = Regex.run(~r/(?<![\d.])(\d{1,2})(?:\.([0-3]))?\s*(?:hh|h\b|hands?)?(?![\d.])/, text) ->
        hands = String.to_integer(Enum.at(m, 1))
        extra = if Enum.at(m, 2) in [nil, ""], do: 0, else: String.to_integer(Enum.at(m, 2))
        if hands in 8..19, do: hands * 4.0 + extra

      true ->
        nil
    end
  end

  @doc "Dated heights in inches, oldest first, from height events and height records."
  def heights(events, records) do
    from_events =
      for e <- events,
          e.event_type == "height",
          date = event_date(e),
          inches = stored(e, "inches") || parse_height("#{e.title} #{e.description}"),
          do: {date, inches, e.inserted_at}

    from_records =
      for r <- records,
          r.record_type == "height",
          inches = parse_height("#{r.title} #{r.description} #{r.notes}"),
          do: {r.date, inches, r.inserted_at}

    one_per_day(from_events ++ from_records)
  end

  @doc "Inches as hands: 58 → \"14.2\", 57.5 → \"14.1½\"."
  def hands(inches) when is_number(inches) do
    whole = trunc(inches / 4)
    rest = inches - whole * 4
    half = if rest - trunc(rest) >= 0.5, do: "½", else: ""
    "#{whole}.#{trunc(rest)}#{half}"
  end

  defp stored(%{metadata: %{} = meta}, key) do
    case meta[key] do
      n when is_number(n) -> n * 1.0
      _ -> nil
    end
  end

  defp stored(_, _), do: nil

  defp one_per_day(entries) do
    entries
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {date, es} ->
      {date, es |> Enum.max_by(&elem(&1, 2), NaiveDateTime) |> elem(1)}
    end)
    |> Enum.sort_by(&Date.to_gregorian_days(elem(&1, 0)))
  end

  @doc "How the latest entry of `type` (\"weight\" or \"height\") was measured, if recorded."
  def latest_method(events, type) do
    events
    |> Enum.filter(&(&1.event_type == type and is_map(&1.metadata) and &1.metadata["method"]))
    |> Enum.max_by(&{Date.to_gregorian_days(event_date(&1)), &1.inserted_at}, fn -> nil end)
    |> then(&(&1 && &1.metadata["method"]))
  end

  # Weigh-ins logged with the weight form keep the number itself.
  defp stored_lbs(%{metadata: %{"lbs" => lbs}}) when is_number(lbs), do: round(lbs)
  defp stored_lbs(_), do: nil

  @doc "How the latest weigh-in was measured (\"scale\", \"tape\", \"estimate\"), if recorded."
  def latest_method(events), do: latest_method(events, "weight")

  defp event_date(%{event_date: %Date{} = d}), do: d
  defp event_date(%{inserted_at: %NaiveDateTime{} = t}), do: NaiveDateTime.to_date(t)
  defp event_date(_), do: nil

  @doc "Same as `weight_trend/1`, for any measurement (heights in inches too)."
  def trend(points), do: weight_trend(points)

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
    if den == 0, do: nil, else: Float.round(num / den, 4)
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

  @doc """
  Each weigh-in, oldest first, with the change since the one before:
  `%{date, lbs, change, days, per_day}` (change, days and per_day nil for the first).
  """
  def rows(points) do
    points
    |> Enum.with_index()
    |> Enum.map(fn {{date, lbs}, i} ->
      prev = if i > 0, do: Enum.at(points, i - 1)

      case prev do
        nil ->
          %{date: date, lbs: lbs, change: nil, days: nil, per_day: nil}

        {pd, pl} ->
          days = Date.diff(date, pd)

          %{
            date: date,
            lbs: lbs,
            change: lbs - pl,
            days: days,
            per_day: if(days > 0, do: Float.round((lbs - pl) / days, 4))
          }
      end
    end)
  end

  @doc "The gain between two weigh-ins (by position, either order): `%{from, to, change, days, per_day}`."
  def compare(points, i, j) do
    [a, b] = Enum.sort([i, j])
    {d1, w1} = Enum.at(points, a)
    {d2, w2} = Enum.at(points, b)
    days = Date.diff(d2, d1)

    %{
      from: {d1, w1},
      to: {d2, w2},
      change: w2 - w1,
      days: days,
      per_day: if(days > 0, do: Float.round((w2 - w1) / days, 4))
    }
  end

  @doc """
  A chart with axes for weigh-ins on a `w` by `h` canvas: the placed points
  `[{x, y, date, lbs}]`, gridlines with pound labels, and a few date labels.
  """
  def chart(points, w, h, opts \\ [])

  def chart(points, w, h, opts) when length(points) >= 2 do
    {left, right, top, bottom} = {40, 14, 24, 26}
    ys = Enum.map(points, &elem(&1, 1))
    range = Enum.max(ys) - Enum.min(ys)
    # opts[:step] keeps gridlines on whole units (4 inches = one hand), widened for long ranges.
    step =
      case opts[:step] do
        nil -> nice_step(range)
        base -> base * max(ceil(range / (base * 4)), 1)
      end

    lo = floor(Enum.min(ys) / step) * step
    hi = max(ceil(Enum.max(ys) / step) * step, lo + step)
    {d0, _} = hd(points)
    {dn, _} = List.last(points)
    span = max(Date.diff(dn, d0), 1)
    x = fn d -> Float.round(left + Date.diff(d, d0) / span * (w - left - right), 1) end
    y = fn v -> Float.round(top + (hi - v) / (hi - lo) * (h - top - bottom), 1) end

    middle = if span > 45, do: [Date.add(d0, div(span, 2))], else: []

    %{
      pts: Enum.map(points, fn {d, v} -> {x.(d), y.(v), d, v} end),
      yticks: for(v <- lo..hi//step, do: {y.(v), v}),
      # First and last labels line up with the chart's edges so they aren't cut off.
      xticks:
        ([{d0, "start"}] ++ Enum.map(middle, &{&1, "middle"}) ++ [{dn, "end"}])
        |> Enum.map(fn {d, anchor} -> {x.(d), Calendar.strftime(d, "%b %-d"), anchor} end),
      left: left,
      right: w - right,
      bottom: h - bottom
    }
  end

  def chart(_points, _w, _h, _opts), do: nil

  # A round gridline step giving about four lines.
  defp nice_step(range) do
    Enum.find([1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500], 1000, &(range / &1 <= 4))
  end
end
