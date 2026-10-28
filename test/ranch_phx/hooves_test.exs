defmodule RanchPhx.HoovesTest do
  use ExUnit.Case, async: true
  alias RanchPhx.Animals.Hooves

  test "angle between two lines, 0–90°, whichever way they're drawn" do
    ground = {{700, 1000}, {1100, 1000}}
    wall = {{915.3, 763.6}, {1100, 1000}}
    assert_in_delta Hooves.angle_between(ground, wall), 52.0, 0.1
    assert_in_delta Hooves.angle_between(ground, {{1100, 1000}, {915.3, 763.6}}), 52.0, 0.1
    assert Hooves.angle_between(ground, {{1, 1}, {1, 1}}) == nil
  end

  test "hoof-pastern axis" do
    assert Hooves.axis(52, 49) == {:straight, -3.0}
    assert {:broken_back, 6.0} = Hooves.axis(50, 56)
    assert {:broken_forward, 7.0} = Hooves.axis(57, 50)
    assert Hooves.axis(52, nil) == nil
    assert Hooves.axis_text(Hooves.axis(50, 56)) == "Broken back 6°"
  end

  test "latest per foot and left/right pairs" do
    ev = fn id, foot, toe, date ->
      %{
        id: id,
        event_type: "hoof",
        event_date: date,
        inserted_at: ~N[2026-10-01 00:00:00],
        photo_urls: [],
        description: nil,
        metadata: %{"foot" => foot, "toe" => toe}
      }
    end

    ms =
      Hooves.measurements([
        ev.(1, "LF", 50.0, ~D[2026-09-01]),
        ev.(2, "LF", 52.5, ~D[2026-10-20]),
        ev.(3, "RF", 53.0, ~D[2026-10-20]),
        ev.(4, "LH", 54.0, ~D[2026-10-20]),
        ev.(5, "RH", 58.5, ~D[2026-10-20])
      ])

    latest = Hooves.latest(ms)
    assert latest["LF"].toe == 52.5
    assert Hooves.pairs(latest) == [{"Fronts", 0.5, :ok}, {"Hinds", 4.5, :check}]

    assert Hooves.title("RF", 52.0, 49.0) ==
             "Right front: toe 52°, pastern 49°, Hoof and pastern line up"
  end
end
