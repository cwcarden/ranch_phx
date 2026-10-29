defmodule RanchPhxWeb.VoiceAskTest do
  # Not async: the API stub is shared.
  use RanchPhxWeb.ConnCase, async: false

  alias RanchPhx.{Accounts, Animals, Training}
  alias RanchPhx.Training.Coach

  setup :register_and_log_in_user

  setup do
    Req.Test.set_req_test_to_shared()

    {:ok, cat} =
      Animals.create_animal(%{name: "Gimels Soldier Cat", barn_name: "Asher", kind: "horse"})

    {:ok, _} = Animals.create_animal(%{name: "Ruby Rose Cowberry", kind: "dog"})

    [program | _] = Training.list_programs()

    {:ok, book} =
      Training.start_book(%{"animal_id" => cat.id}, %{
        "program_id" => program.id,
        "started_on" => "2026-10-01"
      })

    feet = Enum.find(Training.list_activities(), &(&1.slug == "feet"))

    {:ok, _} =
      Training.save_session(%{
        "book_id" => book.id,
        "client_id" => Ecto.UUID.generate(),
        "date" => "2026-10-28",
        "minutes" => "20",
        "note" => "Round pen, left lead sticky",
        "activities" => [%{"activity_id" => feet.id, "result" => "good"}]
      })

    %{cat: cat}
  end

  defp siri(key, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{key}")
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/voice-ask", Jason.encode!(body))
  end

  test "answers from the horse's own training notes, found by his barn name", %{user: user} do
    key = Accounts.create_api_token(user)
    test_pid = self()

    Req.Test.stub(Coach, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:asked, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => "Yesterday Asher did 20 minutes in the round pen; his left lead was sticky."}]
      })
    end)

    resp = siri(key, %{text: "What were yesterday's training notes for Asher?"}) |> json_response(200)
    assert resp["message"] =~ "left lead was sticky"

    assert_received {:asked, %{"messages" => [%{"content" => content}]}}
    assert content =~ "Round pen, left lead sticky"
    assert content =~ "Asher"
    assert content =~ "Question: What were yesterday's training notes for Asher?"
  end

  test "a wrong key is turned away, and an empty question gets a short reply", %{user: user} do
    assert siri("rk_nope", %{text: "Anything?"}) |> json_response(401) |> Map.get("message") =~ "didn't accept"

    key = Accounts.create_api_token(user)
    assert siri(key, %{text: "  "}) |> json_response(422) |> Map.get("message") =~ "didn't catch"
  end

  test "when the AI is down, Siri still gets something to say", %{user: user} do
    key = Accounts.create_api_token(user)
    Req.Test.stub(Coach, fn conn -> conn |> Plug.Conn.put_status(529) |> Req.Test.json(%{"error" => "busy"}) end)

    resp = siri(key, %{text: "When is Asher's Coggins due?"}) |> json_response(200)
    assert resp["ok"] == false
    assert resp["message"] =~ "couldn't get an answer"
  end
end
