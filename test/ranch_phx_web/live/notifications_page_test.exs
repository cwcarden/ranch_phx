defmodule RanchPhxWeb.NotificationsPageTest do
  use RanchPhxWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias RanchPhx.{Animals, LocalTime}

  setup :register_and_log_in_user

  test "notifications and settings open with real-looking data", %{conn: conn} do
    today = LocalTime.today()

    {:ok, a} =
      Animals.create_animal(%{
        name: "Gimels Soldier Cat",
        barn_name: "Asher",
        kind: "horse",
        birth_date: ~D[2025-05-10]
      })

    {:ok, d} = Animals.create_animal(%{name: "Ruby", kind: "dog"})

    rec = fn attrs ->
      {:ok, r} = Animals.create_record(attrs)
      r
    end

    rec.(%{
      "animal_id" => a.id,
      "record_type" => "medication",
      "title" => "Bute",
      "description" => "daily for 5 days",
      "date" => Date.add(today, -1)
    })

    rec.(%{
      "animal_id" => a.id,
      "record_type" => "task",
      "title" => "Soak left front",
      "description" => "daily for 3 days",
      "date" => today
    })

    rec.(%{
      "animal_id" => a.id,
      "record_type" => "deworming",
      "title" => "Panacur",
      "description" => "daily for 5 days",
      "date" => Date.add(today, -10),
      "course_done" => [Date.add(today, -10)]
    })

    rec.(%{
      "animal_id" => d.id,
      "record_type" => "vaccination",
      "title" => "Rabies",
      "date" => Date.add(today, -370),
      "next_due_date" => Date.add(today, -5)
    })

    rec.(%{
      "animal_id" => a.id,
      "record_type" => "coggins",
      "title" => "Coggins",
      "date" => Date.add(today, -300),
      "next_due_date" => Date.add(today, 2)
    })

    {:ok, _} = RanchPhx.Animals.Vitals.log(a, %{temp_f: 101.2}, time: ~T[09:30:00])

    # A reminder already went out: the page shows when.
    user = RanchPhx.Repo.one(from u in RanchPhx.Accounts.User, order_by: [desc: u.id], limit: 1)
    true = RanchPhx.Push.first_time?("morning:#{user.id}:#{Date.to_iso8601(today)}")

    {:ok, _view, html} = live(conn, ~p"/notifications")
    assert html =~ "Last reminder sent: Today"
    assert html =~ "Notifications"
    {:ok, _view, _} = live(conn, ~p"/admin/settings")
  end
end
