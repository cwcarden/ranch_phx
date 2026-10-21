defmodule RanchPhx.TrainingCoachTest do
  # Not async: the Coach runs in a LiveView task in one test, so the API stub is shared.
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.{Animals, Training}
  alias RanchPhx.Training.Coach

  setup do
    Req.Test.set_req_test_to_shared()

    {:ok, animal} =
      Animals.create_animal(%{name: "Asher", kind: "horse", birth_date: ~D[2025-05-10]})

    [program | _] = Training.list_programs()

    {:ok, book} =
      Training.start_book(%{"animal_id" => animal.id}, %{
        "program_id" => program.id,
        "started_on" => "2026-10-01",
        "goal" => "NRCHA Stallion Stakes",
        "goal_date" => "2029-04-15"
      })

    feet = Enum.find(Training.list_activities(), &(&1.slug == "feet"))
    {:ok, issue} = Training.create_issue(book.horse_id, %{"title" => "Left hind"}, ~D[2026-10-01])

    {:ok, _} =
      Training.save_session(%{
        "book_id" => book.id,
        "client_id" => Ecto.UUID.generate(),
        "date" => "2026-10-20",
        "minutes" => "20",
        "activities" => [%{"activity_id" => feet.id, "result" => "trouble", "side" => "left"}],
        "issues" => [
          %{"issue_id" => issue.id, "progress" => "worse", "note" => "Pulled away twice"}
        ]
      })

    {:ok, calls} = Agent.start_link(fn -> [] end)
    %{book: Training.get_book!(book.id), issue: issue, calls: calls}
  end

  # Replies with the given responses in order and records each request body.
  defp stub_claude(calls, responses) do
    Req.Test.stub(Coach, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      n = Agent.get_and_update(calls, fn list -> {length(list), list ++ [Jason.decode!(raw)]} end)
      Req.Test.json(conn, Enum.at(responses, n) || List.last(responses))
    end)
  end

  defp text_reply(text),
    do: %{
      "model" => "claude-sonnet-5-5",
      "stop_reason" => "end_turn",
      "content" => [%{"type" => "text", "text" => text}]
    }

  test "looks things up with a tool, then answers and saves what it checked",
       %{book: book, calls: calls} do
    stub_claude(calls, [
      %{
        "model" => "claude-sonnet-5-5",
        "stop_reason" => "tool_use",
        "content" => [
          %{"type" => "thinking", "thinking" => "", "signature" => "sig"},
          %{
            "type" => "tool_use",
            "id" => "toolu_1",
            "name" => "list_sessions",
            "input" => %{"from" => "2026-10-01", "to" => "2026-10-21", "activity" => "Feet"}
          }
        ]
      },
      text_reply("His left hind has been the sticky one. Keep feet sessions short.")
    ])

    assert {:ok, msg} = Coach.ask(book, "How's his left side been?", ~D[2026-10-21])
    assert msg.answer =~ "left hind"
    assert msg.checked == ["sessions Oct 1–Oct 21 (Feet)"]
    assert [%{id: id}] = Coach.recent(book.id)
    assert id == msg.id

    [first, second] = Agent.get(calls, & &1)
    assert first["model"] == "claude-sonnet-5-5"
    assert first["fallbacks"] == "default"
    assert first["output_config"] == %{"effort" => "medium"}
    assert Enum.all?(first["tools"], &(&1["strict"] == true))
    [prompt] = first["messages"]
    assert prompt["content"] =~ "NRCHA Stallion Stakes"
    assert prompt["content"] =~ "Pulled away twice"

    # The assistant turn goes back unchanged, thinking block included, then the tool result.
    [_, assistant, %{"content" => [result]}] = second["messages"]
    assert Enum.map(assistant["content"], & &1["type"]) == ["thinking", "tool_use"]
    assert result["tool_use_id"] == "toolu_1"
    assert %{"count" => 1, "sessions" => [s]} = Jason.decode!(result["content"])
    assert [%{"name" => "Feet", "result" => "trouble", "side" => "left"}] = s["activities"]
  end

  test "working on history and activity results tools", %{book: book, issue: issue, calls: calls} do
    stub_claude(calls, [
      %{
        "stop_reason" => "tool_use",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "a",
            "name" => "working_on_history",
            "input" => %{"id" => issue.id}
          },
          %{
            "type" => "tool_use",
            "id" => "b",
            "name" => "activity_results",
            "input" => %{"from" => "2026-10-01", "to" => "2026-10-21"}
          }
        ]
      },
      text_reply("Work the left hind a little each day.")
    ])

    assert {:ok, msg} = Coach.ask(book, "What should I work on?", ~D[2026-10-21])
    assert msg.checked == ["history of “Left hind”", "activity results Oct 1–Oct 21"]

    [_, second] = Agent.get(calls, & &1)
    [history, results] = second["messages"] |> List.last() |> Map.get("content")

    assert %{"marks" => [%{"progress" => "worse", "note" => "Pulled away twice"}]} =
             Jason.decode!(history["content"])

    assert %{"activities" => [%{"activity" => "Feet", "times" => 1}]} =
             Jason.decode!(results["content"])
  end

  test "a refusal and an API error come back as friendly errors", %{book: book, calls: calls} do
    stub_claude(calls, [%{"stop_reason" => "refusal", "content" => []}])
    assert {:error, :refusal} = Coach.ask(book, "Hi", ~D[2026-10-21])

    Req.Test.stub(Coach, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => %{"message" => "bad key"}})
    end)

    assert {:error, {:api, 401, _} = reason} = Coach.ask(book, "Hi", ~D[2026-10-21])
    assert Coach.error_message(reason) =~ "API key was rejected"
    assert {:error, :empty} = Coach.ask(book, "  ", ~D[2026-10-21])
    assert Coach.recent(book.id) == []
  end

  describe "on the book page" do
    setup :register_and_log_in_user

    test "ask a suggested question and see the answer", %{conn: conn, book: book, calls: calls} do
      stub_claude(calls, [text_reply("Keep it to two short flag sessions this week.")])
      {:ok, view, _html} = live(conn, ~p"/training/#{book.id}")

      view |> element("#coach button", "What should I work on this week?") |> render_click()
      assert has_element?(view, "#coach-loading")

      assert render_async(view) =~ "Keep it to two short flag sessions this week."
      refute has_element?(view, "#coach-loading")
      assert [%{question: "What should I work on this week?"}] = Coach.recent(book.id)
    end
  end
end
