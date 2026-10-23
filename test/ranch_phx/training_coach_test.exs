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
    assert [%{id: id}] = Coach.recent_threads(book.id)
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
    assert Coach.recent_threads(book.id) == []
  end

  test "a follow-up sends the earlier question and answer and joins the thread",
       %{book: book, calls: calls} do
    stub_claude(calls, [
      text_reply(
        "Stand at his shoulder and ask with light pressure; release on the smallest step."
      ),
      text_reply("Then go back to a smaller ask and slow your timing down.")
    ])

    {:ok, first} = Coach.ask(book, "He won't give me his shoulder on the ground.", ~D[2026-10-21])
    {:ok, second} = Coach.ask(book, "He still crowds me. Now what?", ~D[2026-10-21], first.id)
    assert second.thread_id == first.id

    [_, follow_up] = Agent.get(calls, & &1)
    [q1, a1, latest] = follow_up["messages"]
    assert q1 == %{"role" => "user", "content" => "He won't give me his shoulder on the ground."}
    assert a1["role"] == "assistant" and a1["content"] =~ "smallest step"
    assert latest["content"] =~ "The trainer follows up: \"He still crowds me. Now what?\""
    assert latest["content"] =~ "Snapshot of Asher"

    assert Enum.map(Coach.thread_messages(book.id, second.id), & &1.id) == [first.id, second.id]
    assert [%{id: root}] = Coach.recent_threads(book.id)
    assert root == first.id
    assert first.answer =~ "smallest step"
  end

  test "adds a Working on item when asked, and won't add a duplicate", %{book: book, calls: calls} do
    add = fn id, title ->
      %{
        "stop_reason" => "tool_use",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => id,
            "name" => "add_working_on",
            "input" => %{
              "title" => title,
              "activity" => "groundwork",
              "side" => "left",
              "notes" => "Leans in; ask smaller, release sooner."
            }
          }
        ]
      }
    end

    stub_claude(calls, [
      add.("t1", "Giving his shoulder on the ground"),
      text_reply("Done, it's on his list."),
      add.("t2", "giving his shoulder on the ground"),
      text_reply("That one's already on his list.")
    ])

    {:ok, msg} = Coach.ask(book, "Add that to my list", ~D[2026-10-21])
    assert msg.answer =~ "Added “Giving his shoulder on the ground” to Working on."
    assert msg.checked == []

    item =
      Enum.find(
        Training.list_issues(book.horse_id),
        &(&1.title == "Giving his shoulder on the ground")
      )

    assert %{side: "left", status: "open", notes: "Leans in; ask smaller, release sooner."} = item
    assert item.activity.slug == "groundwork"

    {:ok, again} = Coach.ask(book, "Add it again", ~D[2026-10-21], msg.id)
    refute again.answer =~ "Added"
    [_, _, _, last] = Agent.get(calls, & &1)
    [%{"content" => result}] = last["messages"] |> List.last() |> Map.get("content")
    assert result =~ "already on the Working on list"
    assert Training.list_issues(book.horse_id) |> Enum.count(&(&1.title =~ ~r/shoulder/i)) == 1
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
      assert [%{question: "What should I work on this week?"}] = Coach.recent_threads(book.id)
    end

    test "follow up, start a new question, and reopen an earlier one",
         %{conn: conn, book: book, calls: calls} do
      stub_claude(calls, [
        text_reply("Start with a light ask at his shoulder."),
        text_reply("Slow the timing and ask smaller."),
        text_reply("Two short sessions this week.")
      ])

      {:ok, view, _html} = live(conn, ~p"/training/#{book.id}")
      view |> form("#coach-form", question: "He won't give his shoulder.") |> render_submit()
      render_async(view)

      assert view |> element("#coach-form button[type=submit]") |> render() =~ "Ask follow-up"
      view |> form("#coach-form", question: "He still crowds me.") |> render_submit()
      html = render_async(view)
      assert html =~ "Start with a light ask" and html =~ "Slow the timing"

      view |> element("#coach-new") |> render_click()
      refute render(view) =~ "Slow the timing"
      view |> form("#coach-form", question: "What this week?") |> render_submit()
      assert render_async(view) =~ "Two short sessions"

      view |> element("#coach .tr-earlier", "He won't give his shoulder.") |> render_click()
      html = render(view)
      assert html =~ "Start with a light ask" and html =~ "Slow the timing"
      refute html =~ "Two short sessions this week."
      assert length(Coach.recent_threads(book.id)) == 2
    end
  end
end
