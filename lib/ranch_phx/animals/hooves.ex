defmodule RanchPhx.Animals.Hooves do
  @moduledoc """
  Hoof angles measured from photos: the toe (dorsal wall) angle to the ground, the
  pastern angle, and how the two line up (the hoof-pastern axis). Each measurement
  is a "hoof" timeline event with the marked-up photo.
  """

  @feet [
    {"LF", "Left front"},
    {"RF", "Right front"},
    {"LH", "Left hind"},
    {"RH", "Right hind"}
  ]

  def feet, do: @feet
  def foot_name(code), do: Enum.find_value(@feet, code, fn {c, n} -> c == code && n end)

  # Within this many degrees the hoof and pastern count as lined up, and a pair of
  # feet as matching.
  @axis_ok 3
  @pair_ok 2

  @doc """
  The angle, 0–90°, between line `a` and line `b`, each `{{x1, y1}, {x2, y2}}`.
  """
  def angle_between({{ax1, ay1}, {ax2, ay2}}, {{bx1, by1}, {bx2, by2}}) do
    {ux, uy} = {ax2 - ax1, ay2 - ay1}
    {vx, vy} = {bx2 - bx1, by2 - by1}
    lu = :math.sqrt(ux * ux + uy * uy)
    lv = :math.sqrt(vx * vx + vy * vy)

    if lu == 0 or lv == 0 do
      nil
    else
      cos = abs(ux * vx + uy * vy) / (lu * lv)
      Float.round(:math.acos(min(cos, 1.0)) * 180 / :math.pi(), 1)
    end
  end

  @doc """
  How the pastern lines up with the hoof wall: `{:straight, diff}`,
  `{:broken_back, diff}` (pastern steeper than the hoof, as with a long toe and low
  heel) or `{:broken_forward, diff}` (hoof steeper than the pastern). Nil without both.
  """
  def axis(toe, pastern) when is_number(toe) and is_number(pastern) do
    diff = Float.round((pastern - toe) * 1.0, 1)

    cond do
      abs(diff) <= @axis_ok -> {:straight, diff}
      diff > 0 -> {:broken_back, diff}
      true -> {:broken_forward, -diff}
    end
  end

  def axis(_, _), do: nil

  def axis_text(nil), do: nil
  def axis_text({:straight, _}), do: "Hoof and pastern line up"
  def axis_text({:broken_back, d}), do: "Broken back #{fmt(d)}°"
  def axis_text({:broken_forward, d}), do: "Broken forward #{fmt(d)}°"

  @doc "Hoof events (newest first) as maps with the numbers pulled out."
  def measurements(events) do
    events
    |> Enum.filter(&(&1.event_type == "hoof"))
    |> Enum.map(fn e ->
      m = e.metadata || %{}
      toe = num(m["toe"])
      pastern = num(m["pastern"])

      %{
        id: e.id,
        foot: m["foot"],
        date: e.event_date || NaiveDateTime.to_date(e.inserted_at),
        toe: toe,
        pastern: pastern,
        axis: axis(toe, pastern),
        photo: List.first(e.photo_urls || []),
        note: e.description,
        inserted_at: e.inserted_at
      }
    end)
    |> Enum.filter(&(&1.toe && &1.foot))
    |> Enum.sort_by(&{&1.date, &1.inserted_at}, :desc)
  end

  @doc "The newest measurement for each foot, as a map keyed by foot code."
  def latest(measurements) do
    Enum.reduce(measurements, %{}, fn m, acc -> Map.put_new(acc, m.foot, m) end)
  end

  @doc """
  Left-to-right toe-angle differences for the fronts and hinds:
  `[{"Fronts", 1.5, :ok | :check}]`, only for pairs with both feet measured.
  """
  def pairs(latest) do
    for {label, l, r} <- [{"Fronts", "LF", "RF"}, {"Hinds", "LH", "RH"}],
        a = latest[l],
        b = latest[r],
        a && b do
      d = Float.round(abs(a.toe - b.toe) * 1.0, 1)
      {label, d, if(d <= @pair_ok, do: :ok, else: :check)}
    end
  end

  @doc "A title for the timeline: \"Left front: toe 52.5°, pastern 50°, line up\"."
  def title(foot, toe, pastern) do
    parts =
      ["toe #{fmt(toe)}°"] ++
        if(pastern, do: ["pastern #{fmt(pastern)}°", axis_text(axis(toe, pastern))], else: [])

    "#{foot_name(foot)}: #{Enum.join(parts, ", ")}"
  end

  def fmt(nil), do: "–"

  def fmt(n) do
    r = Float.round(n * 1.0, 1)
    if r == trunc(r), do: "#{trunc(r)}", else: "#{r}"
  end

  defp num(n) when is_number(n), do: n * 1.0

  defp num(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp num(_), do: nil
end
