defmodule RanchPhx.Animals.Hooves do
  @moduledoc """
  Hoof measurements from photos, each a "hoof" timeline event with the marked-up photo:

    * Side view: the toe (dorsal wall) angle to the ground, the pastern angle, and how
      the two line up (the hoof-pastern axis).
    * Sole view (`"view" => "sole"` in the metadata): balance of the bottom of the foot
      from a toe point, the two heels, the widest part and the tip of the frog.

  Also the plain-English summaries and "what's correct" definitions shown with them.
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
    |> Enum.filter(&(&1.event_type == "hoof" and (&1.metadata || %{})["view"] != "sole"))
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

  # ── What the side view means ──────────────────────────────────────────────

  # Usual toe angles, as a rough guide. The best angle for a horse is the one that
  # lines up with his own pastern, so the axis matters more than the number.
  @toe_range %{front: {48, 55}, hind: {50, 57}}

  defp end_of("LF"), do: :front
  defp end_of("RF"), do: :front
  defp end_of(_), do: :hind

  @doc """
  A few short lines on what a side measurement means, each `{:ok | :check | :info, text}`.
  `other` is the newest measurement of the opposite foot (or nil).
  """
  def side_summary(foot, toe, pastern, other \\ nil) do
    {lo, hi} = @toe_range[end_of(foot)]
    which = if end_of(foot) == :front, do: "front", else: "hind"

    toe_line =
      cond do
        toe < lo ->
          {:check,
           "Toe #{fmt(toe)}° is lower than usual for a #{which} foot (about #{lo}–#{hi}°). A low angle often goes with a long toe or low, underrun heels."}

        toe > hi ->
          {:check,
           "Toe #{fmt(toe)}° is steeper than usual for a #{which} foot (about #{lo}–#{hi}°). A steep angle can mean high heels or an upright, boxy foot."}

        true ->
          {:ok,
           "Toe #{fmt(toe)}° is in the usual range for a #{which} foot (about #{lo}–#{hi}°)."}
      end

    axis_line =
      case axis(toe, pastern) do
        nil ->
          {:info, "Draw the pastern line next time to check the hoof-pastern axis."}

        {:straight, _} ->
          {:ok,
           "The pastern lines up with the hoof wall (within #{@axis_ok}°). That straight hoof-pastern axis is what you want."}

        {:broken_back, d} ->
          {:check,
           "Broken back: the pastern is #{fmt(d)}° steeper than the hoof wall. Usually a long toe or low heel; bringing the toe back and supporting the heel lines it up."}

        {:broken_forward, d} ->
          {:check,
           "Broken forward: the hoof wall is #{fmt(d)}° steeper than the pastern. Usually high heels, or a foot heading toward clubby."}
      end

    pair_line =
      case other do
        %{toe: o} when is_number(o) ->
          d = Float.round(abs(toe - o) * 1.0, 1)

          if d <= @pair_ok,
            do:
              {:ok,
               "Within #{fmt(d)}° of the #{foot_name(opposite(foot)) |> String.downcase()}, a good match."},
            else:
              {:check,
               "#{fmt(d)}° off the #{foot_name(opposite(foot)) |> String.downcase()}. Pairs should be within about #{@pair_ok}°."}

        _ ->
          nil
      end

    Enum.reject([toe_line, axis_line, pair_line], &is_nil/1)
  end

  def opposite("LF"), do: "RF"
  def opposite("RF"), do: "LF"
  def opposite("LH"), do: "RH"
  def opposite("RH"), do: "LH"

  @side_correct [
    {"Toe angle",
     "The front of the hoof wall to the ground. Usually about 48–55° in front and 50–57° behind, but the right angle for him is the one that matches his pastern."},
    {"Hoof-pastern axis",
     "Looking from the side, the front of the pastern and the front of the hoof wall should make one straight line (within about 3°). Pastern steeper = broken back; hoof steeper = broken forward."},
    {"Pairs",
     "Left and right fronts should be within about 2° of each other, and the same for the hinds."}
  ]

  @sole_correct [
    {"Toe to heels (frog line)",
     "From the center of the toe to the middle of the heels, down the groove of the frog. This is the foot's center line."},
    {"Widest part",
     "Straight across the bottom at its widest point. On a balanced foot it sits about halfway between toe and heels, so the toe and heel parts are close to 50/50."},
    {"Side to side",
     "The center line should split the widest part into two near-equal halves (within about 4%)."},
    {"Heels",
     "The two heels should sit level with each other, square across the center line (within about 3°). One heel ahead of the other means it's longer or run forward."},
    {"Frog",
     "The tip of the frog should sit on the center line. A frog pulled to one side often points to the foot being uneven."}
  ]

  def side_correct, do: @side_correct
  def sole_correct, do: @sole_correct

  # ── Sole view ───────────────────────────────────────────────────────────────

  # Within these, the sole counts as balanced.
  @toe_share_ok 5
  @sides_ok 4
  @heels_ok 3
  @frog_ok 4

  @doc "Sole events (newest first) as maps with the numbers pulled out."
  def soles(events) do
    events
    |> Enum.filter(&(&1.event_type == "hoof" and (&1.metadata || %{})["view"] == "sole"))
    |> Enum.map(fn e ->
      m = e.metadata || %{}

      %{
        id: e.id,
        view: :sole,
        foot: m["foot"],
        date: e.event_date || NaiveDateTime.to_date(e.inserted_at),
        toe_share: num(m["toe_share"]),
        sides: num(m["sides"]),
        heels: num(m["heels"]),
        frog: num(m["frog"]),
        ratio: num(m["ratio"]),
        photo: List.first(e.photo_urls || []),
        note: e.description,
        inserted_at: e.inserted_at
      }
    end)
    |> Enum.filter(&(&1.toe_share && &1.foot))
    |> Enum.sort_by(&{&1.date, &1.inserted_at}, :desc)
  end

  @doc """
  What a sole measurement means: `{:ok | :check | :info, text}` lines.
  Numbers: toe_share (% of the length ahead of the widest part), sides (% of the
  wider half), heels (degrees out of square), frog (% of the width off center),
  ratio (width ÷ length).
  """
  def sole_summary(%{} = m) do
    t = m.toe_share
    h = Float.round(100 - t, 1)

    toe_line =
      cond do
        t > 50 + @toe_share_ok ->
          {:check,
           "Toe #{fmt(t)}% / heel #{fmt(h)}%: the widest part sits back toward the heels. Usually a long toe or heels run forward."}

        t < 50 - @toe_share_ok ->
          {:check,
           "Toe #{fmt(t)}% / heel #{fmt(h)}%: more of the foot is behind the widest part. Often long or high heels."}

        true ->
          {:ok,
           "Toe #{fmt(t)}% / heel #{fmt(h)}%: the widest part is near the middle, as it should be."}
      end

    side_line =
      if m.sides,
        do:
          if(m.sides - 50 <= @sides_ok,
            do: {:ok, "Sides #{fmt(m.sides)}/#{fmt(100 - m.sides)}: even side to side."},
            else:
              {:check,
               "Sides #{fmt(m.sides)}/#{fmt(100 - m.sides)}: one side is wider. Check for a flare on the wide side or the foot landing unevenly."}
          )

    heel_line =
      if m.heels,
        do:
          if(m.heels <= @heels_ok,
            do: {:ok, "Heels are even (#{fmt(m.heels)}° off square)."},
            else:
              {:check,
               "Heels are #{fmt(m.heels)}° off square: one heel sits further forward or is longer than the other."}
          )

    frog_line =
      case m.frog do
        nil ->
          {:info, "Tap the frog tip next time to check it's centered."}

        f when f <= @frog_ok ->
          {:ok, "The frog points straight down the center line."}

        f ->
          {:check,
           "The frog tip is #{fmt(f)}% of the width off center. Worth showing your farrier."}
      end

    ratio_line =
      if m.ratio,
        do:
          {:info,
           "Width is #{fmt(Float.round(m.ratio * 100, 0))}% of length. Fronts are usually about as wide as long; hinds a little narrower and more pointed."}

    Enum.reject([toe_line, side_line, heel_line, frog_line, ratio_line], &is_nil/1)
  end

  @doc "True when every check on a sole measurement passes."
  def sole_ok?(m), do: Enum.all?(sole_summary(m), fn {s, _} -> s != :check end)

  @doc "Short line for lists: \"Toe 52% · sides 51/49 · heels even\"."
  def sole_short(m) do
    [
      "Toe #{fmt(m.toe_share)}%",
      m.sides && "sides #{fmt(m.sides)}/#{fmt(100 - m.sides)}",
      m.heels && if(m.heels <= @heels_ok, do: "heels even", else: "heels #{fmt(m.heels)}°")
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" · ")
  end

  @doc "A title for the timeline: \"Left front sole: toe 52% / heel 48%, sides 51/49\"."
  def sole_title(foot, m),
    do: "#{foot_name(foot)} sole: #{sole_short(m)}"

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
