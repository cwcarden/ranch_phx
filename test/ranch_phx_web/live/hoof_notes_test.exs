defmodule RanchPhxWeb.HoofNotesTest do
  # Not async: the AI call runs in a LiveView task, so the API stub is shared.
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.Animals
  alias RanchPhx.Training.Coach

  setup :register_and_log_in_user

  setup do
    Req.Test.set_req_test_to_shared()
    {:ok, animal} = Animals.create_animal(%{name: "Asher", kind: "horse"})

    for {foot, toe, pastern} <- [{"LF", 51.0, 50.0}, {"RF", 55.0, 49.0}] do
      {:ok, _} =
        Animals.create_event(%{
          "animal_id" => animal.id,
          "event_type" => "hoof",
          "title" => "#{foot}",
          "event_date" => Date.utc_today(),
          "metadata" => %{"foot" => foot, "toe" => toe, "pastern" => pastern}
        })
    end

    %{animal: animal}
  end

  test "the TrAIner drafts farrier notes from the angles", %{conn: conn, animal: animal} do
    test = self()

    Req.Test.stub(Coach, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, Jason.decode!(raw)})

      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "text",
            "text" => "Fronts are 4° apart.\n- Right front is broken forward 6°."
          }
        ]
      })
    end)

    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")
    view |> element("#ask-notes") |> render_click()
    render_async(view)

    assert has_element?(view, "#notes-text", "Fronts are 4° apart.")
    assert has_element?(view, "#share-notes")

    assert_received {:request, body}
    [%{"content" => [%{"text" => text} | _]}] = body["messages"]
    assert text =~ "Right front" and text =~ "55.0"
  end
end
