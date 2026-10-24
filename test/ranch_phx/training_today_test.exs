defmodule RanchPhx.TrainingTodayTest do
  use ExUnit.Case, async: true

  alias RanchPhx.Training
  alias RanchPhx.Training.Stage

  @today ~D[2026-10-24]
  @stage %Stage{max_sessions_per_week: 4, max_session_minutes: 20, session_types: ["feet"]}
  @feet %{id: 1, slug: "feet", name: "Feet"}
  @ground %{id: 2, slug: "groundwork", name: "Groundwork"}
  @riding %{id: 3, slug: "riding", name: "Riding"}
  @gated MapSet.new(["feet", "riding"])

  defp session(days_ago, minutes \\ 20, activities \\ [@ground]),
    do: %{
      date: Date.add(@today, -days_ago),
      minutes: minutes,
      activities: Enum.map(activities, &%{activity: &1})
    }

  defp issue(title, last, opened_days_ago, activity),
    do: %{
      title: title,
      status: "open",
      activity: activity,
      opened_on: Date.add(@today, -opened_days_ago),
      marks: if(last, do: [%{progress: last}], else: [])
    }

  defp plan(sessions, issues \\ []),
    do: Training.today_plan(@stage, sessions, issues, @gated, @today)

  test "shows the last 7 days, oldest first, with minutes" do
    p = plan([session(0, 15), session(2, 25)])
    assert length(p.days) == 7
    assert List.last(p.days) == %{date: @today, minutes: 15, worked?: true}
    assert Enum.at(p.days, 4) == %{date: Date.add(@today, -2), minutes: 25, worked?: true}
    assert Enum.count(p.days, & &1.worked?) == 2
  end

  test "done once today is logged" do
    assert %{status: :done, reason: "Logged today: 15 min. Nice work."} = plan([session(0, 15)])
  end

  test "rest when the stage's weekly limit is reached" do
    p = plan([session(1), session(3), session(5), session(6)])
    assert p.status == :rest
    assert p.reason =~ "4 of 4 sessions"
  end

  test "rest after three days in a row" do
    p = plan([session(1), session(2), session(3)])
    assert p.status == :rest
    assert p.reason =~ "3 days in a row"
  end

  test "work day says how many sessions are left" do
    p = plan([session(2)])
    assert p.status == :work
    assert p.reason == "3 sessions left in his 7-day limit."
  end

  test "focuses on the stickiest items and suggests allowed activities within the limit" do
    issues = [
      issue("Going well", "better", 30, @ground),
      issue("Left hind", "worse", 5, @feet),
      issue("Brand new", nil, 1, @riding)
    ]

    p = plan([session(2, 45, [@ground, @riding])], issues)
    assert Enum.map(p.focus, & &1.title) == ["Left hind", "Brand new"]
    # Riding isn't part of this stage, so it's never suggested.
    assert Enum.map(p.activities, & &1.name) == ["Feet", "Groundwork"]
    assert p.minutes == 20
  end
end
