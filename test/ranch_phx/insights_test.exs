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

    assert t.latest == 700
    assert_in_delta t.per_day, 0.98, 0.005
    assert t.month_change == %{lbs: 30, days: 31}

    assert Insights.weight_trend([{~D[2026-08-01], 700}, {~D[2026-08-03], 702}]).per_day == nil
    assert Insights.weight_trend([]) == nil
  end

  test "rows show the change and lb/day since the previous weigh-in; any two compare" do
    pts = [{~D[2026-06-06], 640}, {~D[2026-07-16], 690}, {~D[2026-10-01], 775}]

    assert [
             %{lbs: 640, change: nil, per_day: nil},
             %{lbs: 690, change: 50, days: 40, per_day: 1.25},
             %{lbs: 775, change: 85, days: 77, per_day: r3}
           ] = Insights.rows(pts)

    assert_in_delta r3, 1.10, 0.005
    assert %{change: 135, days: 117, per_day: c} = Insights.compare(pts, 2, 0)
    assert_in_delta c, 1.15, 0.005
  end

  test "chart has round gridlines and edge-aligned date labels" do
    ch = Insights.chart([{~D[2026-06-06], 640}, {~D[2026-10-24], 792}], 340, 210)
    assert Enum.map(ch.yticks, &elem(&1, 1)) == [600, 650, 700, 750, 800]
    assert [{_, "Jun 6", "start"}, {_, "Aug 15", "middle"}, {_, "Oct 24", "end"}] = ch.xticks
    assert Insights.chart([{~D[2026-06-06], 640}], 340, 210) == nil
  end

  test "heights read in hands or inches and show as hands" do
    assert Insights.parse_height("14.2 hh") == 58.0
    assert Insights.parse_height("58 in") == 58.0
    assert Insights.parse_height("Grew to 14.1 on the stick") == 57.0
    assert Insights.parse_height("no number") == nil
    assert Insights.hands(58.0) == "14.2"
    assert Insights.hands(57.5) == "14.1½"
  end

  test "height chart gridlines sit on whole hands" do
    ch = Insights.chart([{~D[2026-06-06], 55.0}, {~D[2026-10-24], 58.0}], 340, 210, step: 4)
    assert Enum.map(ch.yticks, &elem(&1, 1)) == [52, 56, 60]
  end
end
