defmodule RanchPhxWeb.VoiceQuickTest do
  use RanchPhxWeb.ConnCase, async: false

  alias RanchPhx.{Accounts, Animals, LocalTime, VoiceNotes, VoiceQuick}

  setup :register_and_log_in_user

  setup do
    RanchPhx.RanchAsk.Memory.forget_all()
    today = LocalTime.today()

    {:ok, cat} =
      Animals.create_animal(%{name: "Gimels Soldier Cat", barn_name: "Asher", kind: "horse"})

    {:ok, ruby} = Animals.create_animal(%{name: "Ruby Rose Cowberry", kind: "dog"})

    {:ok, worm} =
      Animals.create_record(%{
        "animal_id" => cat.id,
        "record_type" => "deworming",
        "title" => "Panacur PowerPac dewormer",
        "description" => "Panacur PowerPac · daily for 5 days",
        "date" => Date.add(today, -2),
        "course_done" => [Date.add(today, -2), Date.add(today, -1)]
      })

    {:ok, _} =
      Animals.create_record(%{
        "animal_id" => ruby.id,
        "record_type" => "vaccination",
        "title" => "Rabies vaccine",
        "date" => Date.add(today, -375),
        "next_due_date" => Date.add(today, -10)
      })

    %{cat: cat, worm: worm, today: today}
  end

  defp siri(key, path, text) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{key}")
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(%{text: text}))
    |> json_response(200)
  end

  test "\"Gave Asher his Panacur\" checks off today's dose right away", %{user: user, worm: worm, today: today} do
    key = Accounts.create_api_token(user)
    resp = siri(key, ~p"/api/voice-log", "Gave Asher his Panacur")
    assert resp["message"] =~ "Checked off Asher's Panacur PowerPac dewormer, day 3 of 5"
    assert today in RanchPhx.Repo.get!(RanchPhx.Animals.Record, worm.id).course_done
    assert VoiceNotes.list_pending() == []

    assert siri(key, ~p"/api/voice-log", "Gave Asher his Panacur")["message"] =~ "already checked off"
  end

  test "\"Asher weighed 805 on the tape\" logs his weight", %{user: user, cat: cat, today: today} do
    key = Accounts.create_api_token(user)
    assert siri(key, ~p"/api/voice-log", "Asher weighed 805 on the tape")["message"] == "Logged Asher at 805 pounds."
    [w] = Animals.get_animal_with_pedigree!(cat.id).timeline_events |> Enum.filter(&(&1.event_type == "weight"))
    assert w.title == "805 lb (tape)" and w.event_date == today and w.metadata["lbs"] == 805
    assert VoiceNotes.list_pending() == []
  end

  test "anything bigger still waits for review", %{user: user} do
    key = Accounts.create_api_token(user)
    assert siri(key, ~p"/api/voice-log", "Worked Asher in the round pen, he did great")["message"] =~ "waiting for you"
    assert [_] = VoiceNotes.list_pending()
  end

  test "\"what's due today\" is answered straight from the records", %{user: user} do
    key = Accounts.create_api_token(user)
    msg = siri(key, ~p"/api/voice-ask", "What's due today?")["message"]
    assert msg =~ "Asher is due Panacur PowerPac dewormer today, day 3 of 5."
    assert msg =~ "Ruby Rose Cowberry's Rabies vaccine is 10 days overdue."

    only = siri(key, ~p"/api/voice-ask", "What's due today for Asher?")["message"]
    refute only =~ "Rabies"
  end

  test "spotting a rundown request" do
    assert VoiceQuick.brief_request?("today")
    assert VoiceQuick.brief_request?("What's due today?")
    assert VoiceQuick.brief_request?("what do I need to do today")
    refute VoiceQuick.brief_request?("What were yesterday's training notes for Asher?")
    refute VoiceQuick.brief_request?("When is Ruby's rabies due?")
  end
end
