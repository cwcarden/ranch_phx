defmodule RanchPhxWeb.VoiceLogTest do
  # Not async: the AI call runs in a LiveView task, so the API stub is shared.
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.{Accounts, Animals, VoiceNotes}
  alias RanchPhx.Training.Coach

  setup :register_and_log_in_user

  setup do
    Req.Test.set_req_test_to_shared()
    {:ok, asher} = Animals.create_animal(%{name: "Asher", kind: "horse"})
    {:ok, ruby} = Animals.create_animal(%{name: "Ruby Rose Cowberry", kind: "dog"})
    %{asher: asher, ruby: ruby}
  end

  defp siri(key, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{key}")
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/voice-log", Jason.encode!(body))
  end

  test "Siri's note is saved for the animal it names, then checked and saved as records",
       %{conn: conn, user: user, asher: asher} do
    key = Accounts.create_api_token(user)

    resp = siri(key, %{text: "Dewormed Asher with Panacur, day 1 of 5"}) |> json_response(200)
    assert resp["message"] =~ "Saved for Asher"

    # Waiting on the home page and the voice log.
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#voice-banner", "1 voice note")

    {:ok, inbox, _} = live(conn, ~p"/voice")
    assert has_element?(inbox, ".vl-text", "Dewormed Asher with Panacur")
    [note] = VoiceNotes.list_pending()

    Req.Test.stub(Coach, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "t1",
            "name" => "add_records",
            "input" => %{
              "records" => [
                %{
                  "record_type" => "deworming",
                  "title" => "Deworming – Panacur",
                  "date" => nil,
                  "next_due_date" => nil,
                  "person" => nil,
                  "location" => nil,
                  "cost" => nil,
                  "description" => "Panacur PowerPac, day 1 of 5"
                }
              ]
            }
          }
        ]
      })
    end)

    {:ok, view, _} = live(conn, ~p"/animals/#{asher.id}?voice=#{note.id}")
    render_async(view)
    assert has_element?(view, "#visit-sheet")
    view |> form("#visit-form") |> render_submit()

    assert [%{title: "Deworming – Panacur"}] = Animals.get_animal_with_pedigree!(asher.id).records
    assert VoiceNotes.list_pending() == []
  end

  test "names two animals: one note each; names none: pick the animal",
       %{conn: conn, user: user, asher: asher, ruby: ruby} do
    key = Accounts.create_api_token(user)

    assert siri(key, %{text: "Fed Asher and Ruby"}) |> json_response(200) |> Map.get("message") =~
             "Asher and Ruby Rose Cowberry"

    assert siri(key, %{text: "Farrier trimmed today"}) |> json_response(200) |> Map.get("message") =~
             "Pick the animal"

    assert VoiceNotes.list_pending() |> Enum.map(& &1.animal_id) |> Enum.sort_by(&(&1 || 0)) ==
             Enum.sort_by([nil, asher.id, ruby.id], &(&1 || 0))

    {:ok, inbox, _} = live(conn, ~p"/voice")
    orphan = Enum.find(VoiceNotes.list_pending(), &is_nil(&1.animal_id))

    inbox
    |> element("#note-#{orphan.id} button[phx-value-animal='#{asher.id}']")
    |> render_click()

    assert has_element?(inbox, "#review-#{orphan.id}")
  end

  test "a wrong or turned-off key is refused", %{user: user} do
    assert siri("rk_nope", %{text: "Fed Asher"}) |> json_response(401)
    key = Accounts.create_api_token(user)
    Accounts.delete_api_token(user)
    assert siri(key, %{text: "Fed Asher"}) |> json_response(401)
    assert VoiceNotes.list_pending() == []
  end

  test "the setup page makes a key once and shows the steps", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/voice")
    assert has_element?(view, "#voice-empty")
    view |> element("#make-key") |> render_click()
    assert has_element?(view, "#new-key")
    assert render(view) =~ "/api/voice-log"
    {:ok, again, _} = live(conn, ~p"/voice")
    refute has_element?(again, "#new-key")
    assert render(again) =~ "Key made"
  end

  test "a horse's barn name finds him: \"Asher\" is Gimels Soldier Cat", %{user: user} do
    {:ok, cat} = Animals.create_animal(%{name: "Gimels Soldier Cat", barn_name: "Smitty", kind: "horse"})
    key = Accounts.create_api_token(user)

    resp = siri(key, %{text: "Trimmed Smitty's fronts, forty five dollars"}) |> json_response(200)
    assert resp["message"] =~ "Saved for Smitty"
    assert [%{animal_id: id}] = VoiceNotes.list_pending()
    assert id == cat.id
  end

  test "saving one note's records leaves the others waiting", %{conn: conn, user: user, asher: asher} do
    key = Accounts.create_api_token(user)
    for t <- ["Dewormed Asher", "Trimmed Asher", "Asher weighed 800"], do: siri(key, %{text: t})
    [n3, n2, n1] = VoiceNotes.list_pending()

    Req.Test.stub(Coach, fn conn ->
      Req.Test.json(conn, %{"content" => [%{"type" => "tool_use", "id" => "t1", "name" => "add_records",
        "input" => %{"records" => [%{"record_type" => "deworming", "title" => "Deworming", "date" => nil,
          "next_due_date" => nil, "person" => nil, "location" => nil, "cost" => nil, "description" => nil}]}}]})
    end)

    {:ok, view, _} = live(conn, ~p"/animals/#{asher.id}?voice=#{n1.id}")
    render_async(view)
    view |> form("#visit-form") |> render_submit()

    assert VoiceNotes.list_pending() |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([n2.id, n3.id])
  end

  describe "training notes" do
    setup %{asher: asher} do
      [program | _] = RanchPhx.Training.list_programs()

      {:ok, book} =
        RanchPhx.Training.start_book(%{"animal_id" => asher.id}, %{
          "program_id" => program.id,
          "started_on" => "2026-10-01"
        })

      %{book: book}
    end

    test "a training note goes to the training log, and saving it clears it from the voice log",
         %{conn: conn, user: user, book: book} do
      key = Accounts.create_api_token(user)
      siri(key, %{text: "Today I worked on picking up Asher's feet and cleaning them"})
      [note] = VoiceNotes.list_pending()

      {:ok, inbox, _} = live(conn, ~p"/voice")
      assert has_element?(inbox, "#train-#{note.id}.tr-btn-primary", "Training session")

      Req.Test.stub(Coach, fn conn ->
        Req.Test.json(conn, %{
          "stop_reason" => "tool_use",
          "content" => [
            %{"type" => "tool_use", "id" => "t1", "name" => "fill_session",
              "input" => %{"date" => nil, "minutes" => 20,
                "activities" => [%{"activity" => "Feet", "result" => "good", "side" => nil, "note" => nil}],
                "working_on" => [], "tags" => [], "note" => "Picked up and cleaned all four"}}
          ]
        })
      end)

      {:ok, view, _} = live(conn, ~p"/training/#{book.id}?voice=#{note.id}")
      render_async(view)
      assert has_element?(view, "#voice-filled")
      view |> form("#session-form") |> render_submit()

      assert RanchPhx.Training.last_session(book.id).note == "Picked up and cleaned all four"
      assert VoiceNotes.list_pending() == []
    end

    test "a note with no care records offers the training log or Mark handled",
         %{conn: conn, user: user, asher: asher} do
      key = Accounts.create_api_token(user)
      siri(key, %{text: "Asher held his foot really well"})
      [note] = VoiceNotes.list_pending()

      Req.Test.stub(Coach, fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "tool_use", "id" => "t1", "name" => "add_records", "input" => %{"records" => []}}]})
      end)

      {:ok, view, _} = live(conn, ~p"/animals/#{asher.id}?voice=#{note.id}")
      render_async(view)
      assert has_element?(view, "#voice-note-other", "Save as a training session")
      view |> element("#voice-note-done") |> render_click()
      assert VoiceNotes.list_pending() == []
    end
  end
end
