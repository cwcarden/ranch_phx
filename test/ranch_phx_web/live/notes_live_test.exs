defmodule RanchPhxWeb.NotesLiveTest do
  # Not async: the AI reads in a LiveView task, so the API stub is shared.
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.{Animals, Notes}
  alias RanchPhx.Training.Coach

  setup :register_and_log_in_user

  setup do
    Req.Test.set_req_test_to_shared()
    {:ok, animal} = Animals.create_animal(%{name: "Asher", kind: "horse"})

    on_exit(fn ->
      File.rm_rf(
        Path.join(Application.app_dir(:ranch_phx, "priv/static"), "uploads/animals/#{animal.id}")
      )
    end)

    %{animal: animal}
  end

  defp stub_read(text) do
    Req.Test.stub(Coach, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(self(), {:asked, Jason.decode!(raw)})

      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => text}]
      })
    end)
  end

  defp write_page(view, meta) do
    render_hook(view, "note_meta", meta)

    for {name, content, type} <- [
          {"page.png", <<137, 80, 78, 71, 13, 10, 26, 10>>, "image/png"},
          {"strokes.json", ~s({"v":1,"strokes":[]}), "application/json"}
        ] do
      f =
        file_input(view, "#note-upload-form", :page, [%{name: name, content: content, type: type}])

      render_upload(f, name)
    end
  end

  test "write a page; the AI reads it; search finds it; write on it again", %{
    conn: conn,
    animal: animal
  } do
    stub_read("Round pen. Stirrups banging, quiet.\nLeft lead sticky [?]")
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/notes")
    assert has_element?(view, "#new-page")

    write_page(view, %{"date" => "2026-10-28", "topic" => "training", "title" => "Round pen"})
    render_async(view)

    [n] = Notes.list(animal.id)
    assert n.topic == "training" and n.title == "Round pen"
    assert n.page_url =~ "/notes/" and n.strokes_url =~ ".json"
    assert n.text =~ "Stirrups banging"
    assert has_element?(view, "#note-text", "Left lead sticky")
    assert has_element?(view, "#write-more")

    # Search looks through the text.
    view |> form("#note-filter", %{q: "stirrups"}) |> render_change()
    assert has_element?(view, "#note-#{n.id}")
    view |> form("#note-filter", %{q: "farrier"}) |> render_change()
    refute has_element?(view, "#note-#{n.id}")
    view |> form("#note-filter", %{q: ""}) |> render_change()
    view |> element("#note-topics button", "Health") |> render_click()
    refute has_element?(view, "#note-#{n.id}")

    # Written on again: same note, new page, old files gone, read again.
    stub_read("Round pen. More written later.")

    write_page(view, %{
      "id" => n.id,
      "date" => "2026-10-28",
      "topic" => "training",
      "title" => "Round pen"
    })

    render_async(view)
    [n2] = Notes.list(animal.id)
    assert n2.id == n.id and n2.page_url != n.page_url
    refute File.exists?(Path.join(Application.app_dir(:ranch_phx, "priv/static"), n.page_url))
    assert n2.text =~ "More written later"
  end

  test "fix the text by hand", %{conn: conn, animal: animal} do
    stub_read("Wormed wth Panacur")
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/notes")
    write_page(view, %{"date" => "2026-10-28", "topic" => "health", "title" => ""})
    render_async(view)
    view |> element("#edit-text") |> render_click()
    view |> form("#text-form", %{text: "Wormed with Panacur, 10 ml"}) |> render_submit()
    assert [%{text: "Wormed with Panacur, 10 ml", title: nil}] = Notes.list(animal.id)

    {:ok, show, _} = live(conn, ~p"/animals/#{animal.id}")
    assert has_element?(show, "#notes-card", "1 page ·")
  end
end
