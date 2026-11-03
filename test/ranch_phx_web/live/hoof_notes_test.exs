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
          "event_date" => RanchPhx.LocalTime.today(),
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

  test "AI places a first guess at the side-view dots", %{conn: conn, animal: animal} do
    test = self()

    Req.Test.stub(Coach, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, Jason.decode!(raw)})

      Req.Test.json(conn, %{
        "stop_reason" => "tool_use",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "t1",
            "name" => "place_dots",
            "input" => %{
              "ground" => [%{"x" => 0.2, "y" => 0.9}, %{"x" => 0.8, "y" => 0.9}],
              "wall" => [%{"x" => 0.6, "y" => 0.5}, %{"x" => 0.75, "y" => 0.9}],
              "pastern" => [],
              "note" => "Pastern is cut off."
            }
          }
        ]
      })
    end)

    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")
    assert has_element?(view, "#hoof-tool[data-ai]")
    render_hook(view, "ai_points", %{"image" => Base.encode64("jpeg"), "view" => "side"})
    render_async(view)

    assert_push_event(view, "ai-points", %{points: points, note: "Pastern is cut off."})
    assert points["wall"] == [%{x: 0.6, y: 0.5}, %{x: 0.75, y: 0.9}]
    assert points["pastern"] == []

    assert_received {:request, body}
    [tool] = body["tools"]
    assert tool["name"] == "place_dots" and tool["strict"] == true
    assert Enum.sort(tool["input_schema"]["required"]) == ~w(ground note pastern wall)
    assert body["system"] =~ "coronary band"
  end
end
