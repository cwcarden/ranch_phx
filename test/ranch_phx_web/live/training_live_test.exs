defmodule RanchPhxWeb.TrainingLiveTest do
  use RanchPhxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RanchPhx.{Animals, Training}

  setup :register_and_log_in_user

  setup do
    {:ok, animal} =
      Animals.create_animal(%{name: "Asher", kind: "horse", birth_date: ~D[2025-05-10]})

    %{animal: animal}
  end

  test "start a book from the training page", %{conn: conn, animal: animal} do
    {:ok, view, _html} = live(conn, ~p"/training?horse=#{animal.id}")
    [program | _] = Training.list_programs()

    assert {:error, {:live_redirect, %{to: "/training/" <> _}}} =
             view
             |> form("#new-book-form",
               book: %{animal_id: animal.id, program_id: program.id, goal: "Stallion Stakes"}
             )
             |> render_submit()

    assert Training.active_book_for_animal(animal.id)
  end

  test "start a book for a horse that isn't on the ranch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/training")
    view |> element("button", "Start a training book") |> render_click()
    view |> element("button", "Another horse") |> render_click()

    assert {:error, {:live_redirect, %{to: "/training/" <> id}}} =
             view
             |> form("#new-book-form", horse: %{name: "Smokey", owner: "J. Smith"})
             |> render_submit()

    assert Training.get_book!(id).horse.name == "Smokey"
  end

  defp act(slug), do: Enum.find(Training.list_activities(), &(&1.slug == slug))

  test "log a session with several activities and see it in the list", %{
    conn: conn,
    animal: animal
  } do
    book = start_book(animal)
    feet = act("feet")

    {:ok, view, html} = live(conn, ~p"/training/#{book.id}")
    assert html =~ "Asher"
    assert html =~ "Log a session"

    view
    |> form("#session-form", session: %{activity_ids: [act("groundwork").id, feet.id]})
    |> render_change()

    html =
      view
      |> form("#session-form",
        session: %{
          activity_ids: [act("groundwork").id, feet.id],
          details: %{"#{feet.id}" => %{result: "trouble", side: "left"}},
          minute_chip: "30",
          tags: ["good"],
          note: "Left hind took a while"
        }
      )
      |> render_submit()

    assert html =~ "Session saved"
    assert html =~ "Groundwork, Feet"
    assert html =~ "Left side"

    assert [%{minutes: 30, activities: [_, %{result: "trouble", side: "left"}]}] =
             Training.list_sessions(book.id)
  end

  test "log a session for an earlier day, then edit it", %{conn: conn, animal: animal} do
    book = start_book(animal)
    {:ok, view, _html} = live(conn, ~p"/training/#{book.id}")
    earlier = Date.utc_today() |> Date.add(-3) |> Date.to_iso8601()
    picks = %{activity_ids: [act("groundwork").id], date_typed: earlier}

    view
    |> form("#session-form", session: picks)
    |> render_change(%{"_target" => ["session", "date_typed"]})

    view |> form("#session-form", session: picks) |> render_submit()

    assert [%{id: id, date: date}] = Training.list_sessions(book.id)
    assert Date.to_iso8601(date) == earlier

    view |> element("#session-#{id} a", "Edit") |> render_click()
    assert render(view) =~ "Edit session"

    view
    |> form("#session-form", session: %{activity_ids: [act("groundwork").id, act("feet").id]})
    |> render_submit()

    assert [%{id: ^id, activities: [_, _]}] = Training.list_sessions(book.id)
  end

  test "repeat last and saved routines fill the form", %{conn: conn, animal: animal} do
    book = start_book(animal)

    {:ok, _} =
      Training.save_session(%{
        "book_id" => book.id,
        "client_id" => Ecto.UUID.generate(),
        "date" => Date.to_iso8601(Date.utc_today()),
        "minutes" => "20",
        "activities" => [%{"activity_id" => act("flag").id}]
      })

    {:ok, view, _html} = live(conn, ~p"/training/#{book.id}")
    view |> element("button", "Repeat last") |> render_click()
    assert view |> element("#detail-#{act("flag").id}") |> has_element?()

    view |> element("button", "Save these picks as a routine") |> render_click()
    view |> form("form[phx-submit=create_routine]", %{name: "Flag day"}) |> render_submit()
    assert [%{name: "Flag day"}] = Training.list_routines(book.horse_id)
    assert render(view) =~ "Flag day"
  end

  test "goals can be added and marked done", %{conn: conn, animal: animal} do
    book = start_book(animal)
    {:ok, view, _html} = live(conn, ~p"/training/#{book.id}")

    view |> element("button", "+ Add goal") |> render_click()

    view
    |> form("#goal-form-new", goal: %{title: "Loads alone", target_date: "2027-03-01"})
    |> render_submit()

    assert [%{id: id, title: "Loads alone"}] = Training.get_book!(book.id).goals
    view |> element("#goal-#{id} button", "Done") |> render_click()
    assert [%{status: "done"}] = Training.get_book!(book.id).goals
  end

  test "customize lists: add an activity", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/training/lists")
    view |> form("form[phx-submit=add_activity]", %{name: "Clippers"}) |> render_submit()
    assert render(view) =~ "Clippers"
    assert Enum.any?(Training.list_activities(), &(&1.name == "Clippers"))
  end

  defp start_book(animal) do
    [program | _] = Training.list_programs()

    {:ok, book} =
      Training.start_book(%{"animal_id" => animal.id}, %{
        "program_id" => program.id,
        "started_on" => Date.utc_today()
      })

    book
  end
end
