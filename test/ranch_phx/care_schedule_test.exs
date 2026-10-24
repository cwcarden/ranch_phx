defmodule RanchPhx.CareScheduleTest do
  use ExUnit.Case, async: true
  alias RanchPhx.Animals.{CareSchedule, CarePreset}

  @today ~D[2026-10-24]

  defp rec(id, type, title, date, due, desc \\ nil),
    do: %{
      id: id,
      record_type: type,
      title: title,
      date: date,
      next_due_date: due,
      description: desc
    }

  defp preset(type, title, value, unit, product \\ nil),
    do: %CarePreset{
      record_type: type,
      title: title,
      interval_value: value,
      interval_unit: unit,
      product: product
    }

  test "next due adds months without spilling into the next month" do
    assert CareSchedule.next_due({:months, 1}, ~D[2026-01-31]) == ~D[2026-02-28]
    assert CareSchedule.next_due({:months, 12}, ~D[2026-10-24]) == ~D[2027-10-24]
    assert CareSchedule.next_due({:weeks, 6}, ~D[2026-10-24]) == ~D[2026-12-05]
    assert CareSchedule.next_due(nil, @today) == nil
  end

  test "knows what a combination vaccine covers, by whole words" do
    assert CareSchedule.covers("vaccination", "Core EQ Innovator") == [
             "ewt",
             "west_nile",
             "rabies"
           ]

    assert CareSchedule.covers("vaccination", "VEWT + WN") == ["ewt"]
    assert CareSchedule.covers("vaccination", "Rhinopneumonitis") == ["rhino_flu"]
    assert CareSchedule.covers("vaccination", "Booster", "given between rounds") == []
    assert CareSchedule.covers("deworming", "West Nile") == []
  end

  test "a combination vaccine satisfies each disease it covers" do
    records = [
      rec(1, "vaccination", "West Nile vaccine", ~D[2025-09-29], ~D[2026-09-29]),
      rec(
        2,
        "vaccination",
        "Core EQ Innovator (EWT, West Nile, Rabies)",
        ~D[2026-10-24],
        ~D[2027-10-24]
      ),
      rec(3, "vaccination", "Rhino/Flu vaccine", ~D[2026-05-01], ~D[2026-11-01])
    ]

    status = CareSchedule.status(records, @today)
    assert Enum.map(status, & &1.record.id) == [3, 2]
    assert hd(tl(status)).covers == ["EWT / Tetanus", "West Nile", "Rabies"]
  end

  test "one deworming schedule whatever the product; planned treatments are separate" do
    records = [
      rec(1, "deworming", "Deworming", ~D[2026-04-01], ~D[2026-10-01], "Quest Plus"),
      rec(2, "deworming", "Deworming", ~D[2026-10-24], ~D[2027-04-24], "Ivermectin"),
      rec(3, "deworming", "Deworming", ~D[2026-10-31], nil, "Panacur PowerPac · daily for 5 days")
    ]

    assert [%{record: %{id: 2}, days: 182}] = CareSchedule.status(records, @today)
    assert [%{id: 3}] = CareSchedule.planned(records, @today)
    assert CareSchedule.due(records, @today) == []
  end

  test "suggests the next date from the matching button's interval" do
    presets = [
      preset("vaccination", "Core EQ Innovator (EWT, West Nile, Rabies)", 12, "months"),
      preset("vaccination", "Rhino/Flu vaccine", 6, "months"),
      preset("deworming", "Deworming", 6, "months", "Ivermectin"),
      preset("health_cert", "Health certificate exam", nil, nil)
    ]

    assert CareSchedule.suggested_due(presets, "vaccination", "WNV booster", @today) ==
             ~D[2027-10-24]

    assert CareSchedule.suggested_due(presets, "vaccination", "Flu", @today) == ~D[2027-04-24]
    assert CareSchedule.suggested_due(presets, "deworming", "Panacur", @today) == ~D[2027-04-24]
    assert CareSchedule.suggested_due(presets, "vaccination", "Strangles", @today) == nil
    assert CareSchedule.suggested_due(presets, "health_cert", "Exam", @today) == nil
  end
end
