defmodule RanchPhx.CareScheduleTest do
  use ExUnit.Case, async: true
  alias RanchPhx.Animals.CareSchedule

  @today ~D[2026-10-24]

  defp rec(type, title, date, due),
    do: %{record_type: type, title: title, date: date, next_due_date: due}

  test "next due adds months without spilling into the next month" do
    assert CareSchedule.next_due({:months, 1}, ~D[2026-01-31]) == ~D[2026-02-28]
    assert CareSchedule.next_due({:months, 12}, ~D[2026-10-24]) == ~D[2027-10-24]
    assert CareSchedule.next_due({:weeks, 6}, ~D[2026-10-24]) == ~D[2026-12-05]
    assert CareSchedule.next_due(nil, @today) == nil
  end

  test "only the latest of each kind counts, soonest first, overdue included" do
    records = [
      rec("vaccination", "West Nile vaccine", ~D[2024-10-01], ~D[2025-10-01]),
      rec("vaccination", "West Nile Vaccine", ~D[2025-09-29], ~D[2026-09-29]),
      rec("deworming", "Deworming", ~D[2026-08-05], ~D[2026-11-03]),
      rec("coggins", "Coggins test", ~D[2026-03-10], ~D[2027-03-10]),
      rec("vet_visit", "Wellness exam", ~D[2026-08-25], nil)
    ]

    assert [%{days: -25, record: %{date: ~D[2025-09-29]}}, %{days: 10}] =
             CareSchedule.due(records, @today)
  end

  test "suggests the usual next date from the type and the vaccine named" do
    assert CareSchedule.suggested_due("horse", "vaccination", "WNV booster", @today) ==
             ~D[2027-10-24]

    assert CareSchedule.suggested_due("horse", "vaccination", "Rhino/Flu", @today) ==
             ~D[2027-04-24]

    assert CareSchedule.suggested_due("horse", "deworming", "Quest Plus", @today) ==
             ~D[2027-01-24]

    assert CareSchedule.suggested_due("horse", "vaccination", "Something new", @today) == nil
    assert CareSchedule.suggested_due("horse", "injury", "Cut on leg", @today) == nil
  end

  test "presets only offer record types that still exist" do
    keys = CareSchedule.presets("horse", ["vaccination", "coggins"]) |> Enum.map(& &1.key)
    assert "west_nile" in keys and "coggins" in keys
    refute "deworming" in keys

    assert Enum.map(CareSchedule.presets("dog", ["vaccination"]), & &1.key) ==
             ["rabies", "dhpp", "bordetella"]
  end
end
