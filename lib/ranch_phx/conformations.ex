defmodule RanchPhx.Conformations do
  @moduledoc """
  Conformation from a side photo of the whole horse: shoulder and hip angles, whether
  he stands uphill or croup-high, body length against height, how the body divides
  into thirds, and neck against back. For the ranch's own horses, and for prospects.

  The dots are placed on the device (or suggested by the AI and corrected by hand);
  the numbers come from them. This module explains what they mean.
  """
  import Ecto.Query
  alias RanchPhx.Repo
  alias RanchPhx.Conformations.Evaluation

  def list(opts \\ []) do
    Evaluation
    |> then(fn q ->
      case opts[:animal_id] do
        nil -> q
        id -> where(q, [e], e.animal_id == ^id)
      end
    end)
    |> order_by([e], desc: e.date, desc: e.id)
    |> preload(:animal)
    |> Repo.all()
  end

  def get(id), do: Evaluation |> Repo.get(id) |> Repo.preload(:animal)

  def create(attrs), do: %Evaluation{} |> Evaluation.changeset(attrs) |> Repo.insert()

  def update(%Evaluation{} = e, attrs), do: e |> Evaluation.changeset(attrs) |> Repo.update()

  def delete(%Evaluation{} = e), do: Repo.delete(e)

  @doc "Who it's of: the animal's name, or the prospect's."
  def who(%Evaluation{animal: %{name: n}}) when is_binary(n), do: n
  def who(%Evaluation{name: n}) when is_binary(n) and n != "", do: n
  def who(_), do: "Prospect"

  def prospect?(%Evaluation{animal_id: nil}), do: true
  def prospect?(_), do: false

  @doc "Short line for lists: \"Shoulder 48° · hip 24° · uphill 1.5%\"."
  def short(e) do
    [
      e.shoulder && "Shoulder #{fmt(e.shoulder)}°",
      e.hip && "hip #{fmt(e.hip)}°",
      e.uphill && uphill_text(e.uphill)
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" · ")
  end

  def uphill_text(u) when u >= 0, do: "uphill #{fmt(u)}%"
  def uphill_text(u), do: "croup-high #{fmt(-u)}%"

  @doc """
  What the numbers mean, each `{:ok | :check | :info, text}`. Conformation is partly
  type and taste, so a lot of it is :info rather than a problem. `age_months` (when
  known) softens croup-high for a horse that's still growing.
  """
  def summary(%Evaluation{} = e, age_months \\ nil) do
    young? = is_integer(age_months) and age_months < 48

    [
      shoulder_line(e.shoulder),
      hip_line(e.hip),
      uphill_line(e.uphill, young?, age_months),
      length_line(e.length_ratio),
      thirds_line(e.thirds),
      neck_line(e.neck_ratio)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp shoulder_line(nil), do: nil

  defp shoulder_line(s) when s > 55,
    do:
      {:check,
       "Shoulder #{fmt(s)}°: upright. A steeper shoulder usually means a shorter, choppier stride and a rougher ride."}

  defp shoulder_line(s) when s < 43,
    do:
      {:info,
       "Shoulder #{fmt(s)}°: very sloping. Long, reaching stride; check the photo is square, since a turned horse reads flatter."}

  defp shoulder_line(s),
    do:
      {:ok, "Shoulder #{fmt(s)}°: a good slope (about 45–55° is typical). Free, reaching stride."}

  defp hip_line(nil), do: nil

  defp hip_line(h) when h < 20,
    do:
      {:info,
       "Hip #{fmt(h)}°: flat. Often more length of stride and speed, a little less power driving from behind."}

  defp hip_line(h) when h > 30,
    do:
      {:info,
       "Hip #{fmt(h)}°: steep. Lots of drive and stop from behind (common in cow horses), with a shorter stride."}

  defp hip_line(h),
    do:
      {:ok,
       "Hip #{fmt(h)}°: in the usual range (about 20–30°). A good balance of drive and stride."}

  defp uphill_line(nil, _, _), do: nil

  defp uphill_line(u, _, _) when u >= -1,
    do:
      {:ok,
       "#{String.capitalize(uphill_text(u))}: withers level with or above the croup. Built to carry weight on the hindquarters and lift the front end."}

  defp uphill_line(u, true, m),
    do:
      {:info,
       "#{String.capitalize(uphill_text(u))}: croup higher than the withers. Normal at #{div(m, 12)} #{if div(m, 12) == 1, do: "year", else: "years"} old; young horses grow in spurts, back end first. Watch it even out."}

  defp uphill_line(u, _, _) when u > -4,
    do:
      {:info,
       "#{String.capitalize(uphill_text(u))}: a little croup-high. Young horses often are while they grow; in a grown horse it puts more weight on the front end."}

  defp uphill_line(u, _, _),
    do:
      {:check,
       "#{String.capitalize(uphill_text(u))}: noticeably croup-high. In a grown horse that puts more weight on the front end and makes collection harder."}

  defp length_line(nil), do: nil

  defp length_line(r) when r > 1.12,
    do:
      {:info,
       "Body length is #{pct(r)} of his height: long through the body. Often smooth-moving; can be harder to collect."}

  defp length_line(r) when r < 0.95,
    do:
      {:info,
       "Body length is #{pct(r)} of his height: short and compact. Handy and quick; check the stride isn't cramped."}

  defp length_line(r),
    do: {:ok, "Body length is #{pct(r)} of his height: balanced, about square."}

  defp thirds_line(nil), do: nil

  defp thirds_line([a, b, c] = t) do
    text = "Shoulder / back / hip: #{Enum.join(t, " / ")}%"

    cond do
      Enum.all?(t, &(&1 >= 27 and &1 <= 40)) ->
        {:ok, "#{text}. About even thirds, a well-balanced body."}

      b == Enum.max(t) ->
        {:info,
         "#{text}. The back is the longest part; a long back can be weaker and harder to round."}

      a == Enum.max(t) ->
        {:info, "#{text}. Lots of shoulder; usually a plus for reach and freedom up front."}

      c == Enum.max(t) ->
        {:info, "#{text}. Lots of hip; usually a plus for power from behind."}

      true ->
        {:info, "#{text}."}
    end
  end

  defp thirds_line(_), do: nil

  defp neck_line(nil), do: nil

  defp neck_line(r) when r >= 1.0,
    do:
      {:ok, "Neck is #{pct(r)} of the back's length: at least as long as the back, as you want."}

  defp neck_line(r) when r >= 0.85,
    do: {:info, "Neck is #{pct(r)} of the back's length: a little short for his back."}

  defp neck_line(r),
    do:
      {:check,
       "Neck is #{pct(r)} of the back's length: short for his back, which can make balance and flexion harder."}

  @correct [
    {"Shoulder angle",
     "Top of the shoulder blade to the point of the shoulder, against the ground. About 45–55°. Sloping gives a longer, smoother stride; upright, a shorter, choppier one."},
    {"Hip angle",
     "Point of the hip to the point of the buttock, against the ground. About 20–30°. Flatter: more stride and speed. Steeper: more drive and stop."},
    {"Uphill or croup-high",
     "Height at the withers compared with the top of the croup. Level or uphill carries weight on the hindquarters. Young horses are often croup-high while growing."},
    {"Body length",
     "Point of the shoulder to point of the buttock, compared with height at the withers. About the same (square) is balanced."},
    {"Thirds",
     "Straight-line lengths of the shoulder (point of shoulder to withers), back (withers to point of hip) and hip (point of hip to point of buttock). About a third each."},
    {"Neck",
     "Poll to withers, compared with the back (withers to point of hip). The neck at least as long as the back."},
    {"The photo",
     "Standing square on level ground, head up and straight, camera level at mid-barrel and square to his side, 15–20 feet back. A turned or tilted horse reads wrong."}
  ]

  def correct, do: @correct

  def fmt(nil), do: "–"

  def fmt(n) do
    r = Float.round(n * 1.0, 1)
    if r == trunc(r), do: "#{trunc(r)}", else: "#{r}"
  end

  defp pct(r), do: "#{round(r * 100)}%"
end
