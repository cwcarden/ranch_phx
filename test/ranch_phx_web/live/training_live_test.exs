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

  test "log a session and see it in the list", %{conn: conn, animal: animal} do
    book = start_book(animal)

    {:ok, view, html} = live(conn, ~p"/training/#{book.id}")
    assert html =~ "Asher"
    assert html =~ "Log a session"

    html =
      view
      |> form("#session-form",
        session: %{
          session_type: "flag",
          minute_chip: "15",
          tags: ["good"],
          note: "Stood quiet for the flag"
        }
      )
      |> render_submit()

    assert html =~ "Session saved"
    assert html =~ "Stood quiet for the flag"
    assert [%{session_type: "flag", minutes: 15}] = Training.list_sessions(book.id)
  end

  test "log a session for an earlier day", %{conn: conn, animal: animal} do
    book = start_book(animal)
    {:ok, view, _html} = live(conn, ~p"/training/#{book.id}")
    earlier = Date.utc_today() |> Date.add(-3) |> Date.to_iso8601()

    view
    |> form("#session-form", session: %{session_type: "groundwork", date_typed: earlier})
    |> render_change(%{"_target" => ["session", "date_typed"]})

    view
    |> form("#session-form", session: %{session_type: "groundwork", date_typed: earlier})
    |> render_submit()

    assert [%{date: date}] = Training.list_sessions(book.id)
    assert Date.to_iso8601(date) == earlier
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
