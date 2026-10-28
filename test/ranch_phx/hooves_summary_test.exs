defmodule RanchPhx.HoovesSummaryTest do
  use ExUnit.Case, async: true
  alias RanchPhx.Animals.Hooves

  test "side summary: range, axis and the matching foot" do
    lines = Hooves.side_summary("LF", 52.0, 53.0, %{toe: 53.0})

    assert [{:ok, "Toe 52° is in the usual range" <> _}, {:ok, _}, {:ok, "Within 1°" <> _}] =
             lines

    assert [{:check, "Toe 58° is steeper" <> _}, {:check, "Broken forward" <> _}] =
             Hooves.side_summary("LH", 58.0, 50.0)

    assert [{:ok, _}, {:info, "Draw the pastern line" <> _}] =
             Hooves.side_summary("RH", 54.0, nil)
  end

  test "sole summary and the balanced check" do
    good = %{toe_share: 51.0, sides: 52.0, heels: 1.0, frog: 1.0, ratio: 1.0}
    assert Hooves.sole_ok?(good)
    assert Hooves.sole_short(good) == "Toe 51% · sides 52/48 · heels even"

    bad = %{good | heels: 6.0, frog: 9.0}
    refute Hooves.sole_ok?(bad)
    text = bad |> Hooves.sole_summary() |> Enum.map_join(" ", &elem(&1, 1))
    assert text =~ "Heels are 6° off square"
    assert text =~ "frog tip is 9% of the width off center"
  end

  test "sole events stay out of the side angles and the other way round" do
    side = %{
      id: 1,
      event_type: "hoof",
      metadata: %{"foot" => "LF", "toe" => 52},
      event_date: ~D[2026-10-01],
      photo_urls: [],
      description: nil,
      inserted_at: ~N[2026-10-01 00:00:00]
    }

    sole = %{
      side
      | id: 2,
        metadata: %{
          "view" => "sole",
          "foot" => "LF",
          "toe_share" => 50,
          "sides" => 51,
          "heels" => 1
        }
    }

    assert [%{id: 1}] = Hooves.measurements([side, sole])
    assert [%{id: 2, view: :sole}] = Hooves.soles([side, sole])
  end

  test "the traced white line's side-to-side split" do
    m = %{toe_share: 50.0, sides: 51.0, heels: 1.0, frog: 1.0, ratio: 1.0, area: 51.5}
    assert Hooves.sole_ok?(m)
    assert m |> Hooves.sole_summary() |> Enum.any?(&match?({:ok, "Sole area 51.5/48.5" <> _}, &1))

    refute Hooves.sole_ok?(%{m | area: 57.0})
    assert %{m | area: 57.0} |> Hooves.sole_summary() |> Enum.any?(&match?({:check, "Sole area 57/43" <> _}, &1))
  end
end
