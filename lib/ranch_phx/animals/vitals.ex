defmodule RanchPhx.Animals.Vitals do
  @moduledoc """
  Temperature, pulse and breathing, kept as timeline events of type "vitals" (several a
  day, each with its time). Read from plain words ("Asher's temp was 100.2", "pulse 40,
  resp 12", "38.1 degrees C"), checked against the normal range for the kind of animal,
  and listed newest first for the Vitals page.

  Each event's metadata: "temp_f" (float), "pulse" (beats a minute), "resp" (breaths a
  minute), "source" ("siri", "app"), any of them missing.
  """
  import Ecto.Query, only: [from: 2]
  alias RanchPhx.{Animals, LocalTime, Repo}
  alias RanchPhx.Animals.{Animal, TimelineEvent}

  # ── Reading them from words ──

  @temp_word ~r/\b(?:temp(?:erature)?s?|vitals?|fever|thermometer)\b[^\d]{0,25}?(\d{2,3}(?:\.\d+)?)\s*(°|degrees?|deg\b)?\s*([cf])?\b/iu
  @temp_unit ~r/(?<![\d.])(\d{2,3}(?:\.\d+)?)\s*(?:°\s*([cf])?|degrees?\s*([cf](?:ahrenheit|elsius)?)?\b|deg\b)/iu
  @pulse ~r/\b(?:pulse|heart\s*rate|heart\s*beat|hr)\b[^\d]{0,15}?(\d{2,3})\b|(?<![\d.])(\d{2,3})\s*(?:bpm|beats)\b/i
  @resp ~r/\b(?:resp(?:iration|irations|iratory(?:\s+rate)?)?s?|breathing(?:\s+rate)?|breaths?|rr)\b[^\d]{0,15}?(\d{1,3})\b|(?<![\d.])(\d{1,3})\s*(?:breaths?|respirations?)\b/i

  @doc """
  The vitals in `text`: `%{temp_f:, pulse:, resp:}` with any it didn't find left nil,
  or nil when there are none. Celsius (anything under 45°) becomes Fahrenheit.
  """
  def parse(text) do
    t = to_string(text)

    temp =
      case Regex.run(@temp_word, t) || Regex.run(@temp_unit, t) do
        nil -> nil
        m -> m |> Enum.at(1) |> to_f(unit(m)) |> in_range(85.0, 110.0)
      end

    pulse = t |> first(@pulse) |> in_range(10, 250)
    resp = t |> first(@resp) |> in_range(4, 120)

    if temp || pulse || resp, do: %{temp_f: temp, pulse: pulse, resp: resp}
  end

  @doc "A clock time said in `text` (\"at 9:30 AM\", \"at 7 pm\", \"at 14:15\"), or nil."
  def parse_time(text) do
    case Regex.run(
           ~r/\bat\s+(\d{1,2})(?::(\d{2}))?\s*(a\.?\s?m\.?|p\.?\s?m\.?)?(?![\d.°])/i,
           to_string(text)
         ) do
      [_, h, min_said | rest] ->
        h = String.to_integer(h)
        min = if min_said in [nil, ""], do: 0, else: String.to_integer(min_said)
        ap = rest |> List.first() |> to_string() |> String.downcase() |> String.first()

        h =
          case ap do
            "p" when h < 12 -> h + 12
            "a" when h == 12 -> 0
            _ -> h
          end

        # A bare "at 9" with no a.m./p.m. or minutes is too likely something else.
        if (ap in ["a", "p"] or min_said not in [nil, ""]) and h in 0..23 and min in 0..59,
          do: Time.new!(h, min, 0)

      _ ->
        nil
    end
  end

  defp unit(m) do
    m
    |> Enum.drop(2)
    |> Enum.find("", &(&1 not in [nil, ""] and &1 =~ ~r/^[cf]/i))
    |> String.downcase()
    |> String.first()
  end

  defp to_f(s, u) do
    {n, _} = Float.parse(s)

    cond do
      u == "c" -> c_to_f(n)
      u != "f" and n <= 45 -> c_to_f(n)
      true -> Float.round(n * 1.0, 1)
    end
  end

  defp c_to_f(c), do: Float.round(c * 9 / 5 + 32, 1)

  defp first(t, re) do
    case Regex.run(re, t) do
      nil -> nil
      m -> m |> Enum.drop(1) |> Enum.find(&(&1 not in [nil, ""])) |> String.to_integer()
    end
  end

  defp in_range(nil, _, _), do: nil
  defp in_range(v, lo, hi), do: if(v >= lo and v <= hi, do: v)

  # ── Normal ranges ──

  @doc """
  Normal resting ranges for the animal: `%{temp_f: {lo, hi}, fever_f: over_this, pulse:
  {lo, hi}, resp: {lo, hi}}`. Between the top of normal and `fever_f` a temperature is
  "slightly high"; above it, a fever. Foals under six months run warmer and faster. Nil
  for kinds without a set range.
  """
  def ranges(%Animal{kind: "horse"} = a) do
    if months_old(a) < 6,
      do: %{temp_f: {100.0, 102.0}, fever_f: 102.5, pulse: {60, 100}, resp: {20, 40}},
      else: %{temp_f: {99.0, 101.0}, fever_f: 101.5, pulse: {28, 44}, resp: {10, 24}}
  end

  def ranges(%Animal{kind: "dog"}),
    do: %{temp_f: {101.0, 102.5}, fever_f: 103.0, pulse: {60, 140}, resp: {10, 35}}

  def ranges(%Animal{kind: "cat"}),
    do: %{temp_f: {100.5, 102.5}, fever_f: 103.0, pulse: {140, 220}, resp: {20, 30}}

  def ranges(%Animal{kind: k}) when k in ["cow", "cattle"],
    do: %{temp_f: {100.4, 102.8}, fever_f: 103.0, pulse: {48, 84}, resp: {26, 50}}

  def ranges(%Animal{kind: k}) when k in ["goat", "sheep"],
    do: %{temp_f: {101.5, 103.5}, fever_f: 104.0, pulse: {70, 90}, resp: {12, 20}}

  def ranges(_), do: nil

  @doc "True for a foal under six months (its own, warmer ranges)."
  def foal?(%Animal{kind: "horse"} = a), do: months_old(a) < 6
  def foal?(_), do: false

  defp months_old(%Animal{birth_date: nil}), do: 999
  defp months_old(%Animal{birth_date: d}), do: div(Date.diff(LocalTime.today(), d), 30)

  @doc ":low, :normal, :high or nil (no value or no range)."
  def status(nil, _), do: nil
  def status(_, nil), do: nil
  def status(v, {lo, _hi}) when v < lo, do: :low
  def status(v, {_lo, hi}) when v > hi, do: :high
  def status(_, _), do: :normal

  @doc """
  How a reading compares for this animal. Temperature: :low, :normal, :elevated
  (above normal, not a fever) or :fever. Pulse and breathing: :low, :normal or :high.
  """
  def status_of(%Animal{} = a, :temp_f, v) do
    case {ranges(a), v} do
      {nil, _} -> nil
      {_, nil} -> nil
      {%{temp_f: {lo, _}}, v} when v < lo -> :low
      {%{temp_f: {_, hi}}, v} when v <= hi -> :normal
      {%{fever_f: f}, v} when v <= f -> :elevated
      _ -> :fever
    end
  end

  def status_of(%Animal{} = a, key, v), do: status(v, a |> ranges() |> then(&(&1 && &1[key])))

  @doc "One plain line on what a reading means, for under it in the timeline; nil when normal."
  def meaning(%Animal{} = a, key, v) do
    r = ranges(a)

    case {key, status_of(a, key, v)} do
      {:temp_f, :elevated} ->
        "Slightly above normal, not a fever (fever is over #{num(r.fever_f)} °F). Recheck later, at rest."

      {:temp_f, :fever} ->
        "Fever range (over #{num(r.fever_f)} °F). Call the vet, sooner if he's off his feed or dull."

      {:temp_f, :low} ->
        "Below normal. Take it again (all the way in, until it beeps). If it stays low or he seems dull or cold, call the vet."

      {:pulse, :high} ->
        "Faster than resting. Recheck once he's calm; pain, fever or heat can raise it."

      {:pulse, :low} ->
        "Below the usual resting range. Fit horses can run low; recheck."

      {:resp, :high} ->
        "Breathing faster than resting. Recheck once he's calm and cool."

      {:resp, :low} ->
        "Below the usual range. Recheck."

      _ ->
        nil
    end
  end

  # ── Saving and listing ──

  @doc "Saves one reading. `vitals` from `parse/1` (or the form), plus when and a note."
  def log(%Animal{} = a, vitals, opts \\ []) do
    date = opts[:date] || LocalTime.today()
    time = opts[:time] || LocalTime.now() |> NaiveDateTime.to_time() |> Time.truncate(:second)

    meta =
      %{
        "temp_f" => vitals[:temp_f],
        "pulse" => vitals[:pulse],
        "resp" => vitals[:resp],
        "source" => opts[:source] || "app"
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    Animals.create_event(%{
      "animal_id" => a.id,
      "event_type" => "vitals",
      "title" => describe(meta),
      "description" => opts[:note],
      "event_date" => date,
      "event_time" => time,
      "metadata" => meta
    })
  end

  @doc "Readings for an animal, newest first."
  def list(animal_id) do
    Repo.all(
      from e in TimelineEvent,
        where: e.animal_id == ^animal_id and e.event_type == "vitals",
        order_by: [desc: e.event_date, desc_nulls_last: e.event_time, desc: e.id]
    )
  end

  @doc "\"Temp 100.2 °F · pulse 40 · resp 12\""
  def describe(meta) do
    [
      meta["temp_f"] && "Temp #{fmt_both(meta["temp_f"])}",
      meta["pulse"] && "pulse #{meta["pulse"]}",
      meta["resp"] && "resp #{meta["resp"]}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
    |> then(&(String.upcase(String.first(&1) || "") <> String.slice(&1, 1..-1//1)))
  end

  def fmt_temp(nil), do: nil
  def fmt_temp(f), do: "#{:erlang.float_to_binary(f * 1.0, decimals: 1)} °F"

  @doc "\"38.4 °C\" for a Fahrenheit reading."
  def fmt_c(nil), do: nil
  def fmt_c(f), do: "#{:erlang.float_to_binary((f - 32) * 5 / 9, decimals: 1)} °C"

  @doc "\"101.2 °F (38.4 °C)\""
  def fmt_both(nil), do: nil
  def fmt_both(f), do: "#{fmt_temp(f)} (#{fmt_c(f)})"

  @doc "What Siri says back after saving a reading."
  def spoken(%Animal{} = a, v) do
    name = Animal.display_name(a)
    r = ranges(a)

    parts =
      [
        v.temp_f &&
          {"temperature #{:erlang.float_to_binary(v.temp_f * 1.0, decimals: 1)} degrees", :temp_f,
           v.temp_f},
        v.pulse && {"pulse #{v.pulse}", :pulse, v.pulse},
        v.resp && {"respiration #{v.resp}", :resp, v.resp}
      ]
      |> Enum.filter(& &1)

    said = parts |> Enum.map(&elem(&1, 0)) |> join_and()

    statuses = for {_, key, val} <- parts, do: {key, status_of(a, key, val)}
    temp = Keyword.get(statuses, :temp_f)

    temp_text =
      case temp do
        :elevated ->
          " That's slightly above normal (#{range_words(r.temp_f)}) but not a fever. Check it again later, at rest."

        :fever ->
          " That's a fever (over #{num(r.fever_f)}). If it stays up or he's off his feed, call the vet."

        :low ->
          " That's below normal (#{range_words(r.temp_f)}). Take it again to be sure."

        _ ->
          ""
      end

    others =
      for {key, s} <- statuses, key != :temp_f, s in [:high, :low] do
        "#{label(key)} is #{s} (normal #{range_words(r[key])})"
      end

    tail =
      cond do
        r == nil ->
          ""

        temp in [nil, :normal] and others == [] ->
          " That's normal."

        true ->
          temp_text <>
            if(others == [], do: "", else: " " <> String.capitalize(join_and(others)) <> ".")
      end

    "Logged #{name}'s #{said}." <> tail
  end

  defp label(:temp_f), do: "temperature"
  defp label(:pulse), do: "pulse"
  defp label(:resp), do: "respiration"

  defp range_words({lo, hi}), do: "#{num(lo)} to #{num(hi)}"

  defp num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp num(n), do: to_string(n)

  defp join_and([one]), do: one
  defp join_and([a, b]), do: "#{a} and #{b}"
  defp join_and(list), do: Enum.join(Enum.drop(list, -1), ", ") <> " and " <> List.last(list)
end
