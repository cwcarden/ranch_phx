defmodule RanchPhx.InsightsTest do
  use ExUnit.Case, async: true
  alias RanchPhx.Animals.Insights

  test "reads weights from what was typed" do
    assert Insights.parse_weight("780 lb by tape") == 780
    assert Insights.parse_weight("Weighed 1,050 lbs") == 1050
    assert Insights.parse_weight("354 kg") == 780
    assert Insights.parse_weight("Gained 15 lb, now 805 lb") == 805
    assert Insights.parse_weight("Weight 12/3: 690") == 690
    assert Insights.parse_weight("Weight") == nil
  end

  defp event(date, title, meta \\ %{}),
    do: %{
      event_type: "weight",
      event_date: date,
      title: title,
      description: nil,
      metadata: meta,
      inserted_at: ~N[2026-10-24 12:00:00]
    }

  test "uses the stored number from the weight form and one weigh-in per day" do
    events = [
      event(~D[2026-06-01], "640 lb"),
      event(~D[2026-08-01], "something", %{"lbs" => 700, "method" => "scale"}),
      %{
        event_type: "note",
        event_date: ~D[2026-08-02],
        title: "900 lb",
        description: nil,
        metadata: %{},
        inserted_at: ~N[2026-10-24 12:00:00]
      }
    ]

    records = [
      %{
        record_type: "weight",
        date: ~D[2026-09-01],
        title: "Weight",
        description: "730 lb by tape",
        notes: nil,
        inserted_at: ~N[2026-10-24 12:00:00]
      }
    ]

    assert Insights.weights(events, records) ==
             [{~D[2026-06-01], 640}, {~D[2026-08-01], 700}, {~D[2026-09-01], 730}]

    assert Insights.latest_method(events) == "scale"
  end

  test "average daily gain is a straight-line fit; needs two weigh-ins a week apart" do
    t =
      Insights.weight_trend([{~D[2026-06-01], 640}, {~D[2026-07-01], 670}, {~D[2026-08-01], 700}])

    assert t.latest == 700 and t.per_day == 0.98
    assert t.month_change == %{lbs: 30, days: 31}

    assert Insights.weight_trend([{~D[2026-08-01], 700}, {~D[2026-08-03], 702}]).per_day == nil
    assert Insights.weight_trend([]) == nil
  end
end
