defmodule RanchPhxWeb.HealthRecordTest do
  use RanchPhxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RanchPhx.{Animals, LocalTime}

  setup :register_and_log_in_user

  setup do
    today = LocalTime.today()

    {:ok, cat} =
      Animals.create_animal(%{
        name: "Gimels Soldier Cat",
        barn_name: "Asher",
        kind: "horse",
        registration_number: "6456194",
        birth_date: ~D[2025-05-10]
      })

    rec = fn attrs -> {:ok, r} = Animals.create_record(Map.put(attrs, "animal_id", cat.id)); r end

    rec.(%{"record_type" => "vaccination", "title" => "Core EQ Innovator (EWT, West Nile, Rabies)",
      "description" => "Lot 123A", "date" => Date.add(today, -5), "next_due_date" => Date.add(today, 360), "person" => "Dr. Hall"})
    rec.(%{"record_type" => "coggins", "title" => "Coggins test", "description" => "Negative",
      "date" => Date.add(today, -300), "next_due_date" => Date.add(today, 10)})
    rec.(%{"record_type" => "deworming", "title" => "Panacur PowerPac dewormer",
      "description" => "Panacur PowerPac · daily for 5 days", "date" => Date.add(today, -2),
      "course_done" => [Date.add(today, -2)]})
    rec.(%{"record_type" => "trim", "title" => "Hoof trim", "date" => Date.add(today, -20), "person" => "Jake"})
    rec.(%{"record_type" => "round_pen", "title" => "Round pen", "date" => Date.add(today, -1)})

    %{cat: cat}
  end

  test "the health record lists what's current or due and every health record, by kind", %{conn: conn, cat: cat} do
    html = conn |> get(~p"/animals/#{cat.id}/health") |> html_response(200)

    assert html =~ "Health Record"
    assert html =~ "Asher"
    assert html =~ "Registered name"
    assert html =~ "Gimels Soldier Cat"
    assert html =~ "6456194"

    # At a glance: Coggins due within the month, the vaccine current.
    assert html =~ "Current status"
    assert html =~ ~r/Coggins test.*?Due in 10d/s
    assert html =~ "Current"

    # Grouped history.
    assert html =~ "Vaccinations"
    assert html =~ "Lot 123A"
    assert html =~ "Dr. Hall"
    assert html =~ "Coggins &amp; lab tests"
    assert html =~ "Deworming"
    assert html =~ "1 of 5 doses checked"
    assert html =~ "Hoof care (recent)"

    # Not health: training records stay out.
    refute html =~ "Round pen"
  end

  test "the animal page links to it", %{conn: conn, cat: cat} do
    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}?tab=records")
    assert has_element?(view, "#health-record-link[href='/animals/#{cat.id}/health']")
    assert has_element?(view, "#act-health")
  end
end
