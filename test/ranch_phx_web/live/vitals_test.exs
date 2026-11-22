defmodule RanchPhxWeb.VitalsTest do
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.{Accounts, Animals, LocalTime, VoiceNotes}
  alias RanchPhx.Animals.Vitals

  setup :register_and_log_in_user

  setup do
    {:ok, cat} =
      Animals.create_animal(%{
        name: "Gimels Soldier Cat",
        barn_name: "Asher",
        kind: "horse",
        birth_date: ~D[2025-05-10]
      })

    %{cat: cat}
  end

  defp siri(key, text) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{key}")
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/voice-log", Jason.encode!(%{text: text}))
    |> json_response(200)
  end

  test "reads temperatures, pulse and breathing the way they're said" do
    assert %{temp_f: 100.0} = Vitals.parse("Asher's vitals were 100°F today")

    assert %{temp_f: 101.2} =
             Vitals.parse("Checked Asher's vitals he was 101.2 Fahrenheit at 9:30 AM today")

    assert %{temp_f: 101.1} = Vitals.parse("His temperature is 38.4 C")
    assert %{pulse: 40, resp: 12} = Vitals.parse("pulse 40, resp 12")

    assert %{temp_f: 99.8, pulse: 44, resp: 20} =
             Vitals.parse("temp was 99.8 F, pulse 44, respiration 20")

    assert Vitals.parse("Asher weighed 805") == nil
    assert Vitals.parse("Gave Asher his Panacur") == nil

    assert Vitals.parse_time("he was 101.2 Fahrenheit at 9:30 AM today") == ~T[09:30:00]
    assert Vitals.parse_time("at 7 pm") == ~T[19:00:00]
    assert Vitals.parse_time("temp 100 at the barn") == nil
  end

  test "Siri logs a temperature straight to Vitals and says if it's high", %{user: user, cat: cat} do
    key = Accounts.create_api_token(user)

    msg = siri(key, "Checked Asher's vitals he was 101.2 Fahrenheit at 9:30 AM today")["message"]
    assert msg =~ "Logged Asher's temperature 101.2 degrees."
    assert msg =~ "slightly above normal (99.0 to 101.0) but not a fever"
    assert VoiceNotes.list_pending() == []

    [r] = Vitals.list(cat.id)
    assert r.metadata["temp_f"] == 101.2 and r.event_time == ~T[09:30:00]
    assert r.event_date == LocalTime.today()

    assert siri(key, "Asher's temp is 100.1")["message"] =~ "That's normal."
    assert siri(key, "Asher's temp is 102.4")["message"] =~ "That's a fever (over 101.5)"
  end

  test "a waiting Siri note from yesterday is saved for yesterday", %{
    conn: conn,
    user: user,
    cat: cat
  } do
    {:ok, [note]} = VoiceNotes.create_from_text(user, "Asher's vitals were 100°F today")

    yesterday = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
    note |> Ecto.Changeset.change(inserted_at: yesterday) |> RanchPhx.Repo.update!()

    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}?voice=#{note.id}")
    assert render(view) =~ "Logged Asher&#39;s temperature 100.0 degrees"
    [r] = Vitals.list(cat.id)
    assert r.event_date == Date.add(LocalTime.today(), -1)
    assert VoiceNotes.list_pending() == []
  end

  test "typing it in the records box saves it too", %{conn: conn, cat: cat} do
    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}?tab=records")
    render_hook(view, "rec_voice_draft", %{"spoken" => "temp 100.4, pulse 36"})
    assert [%{metadata: %{"temp_f" => 100.4, "pulse" => 36}}] = Vitals.list(cat.id)
    assert render(view) =~ "Logged Asher&#39;s temperature 100.4 degrees and pulse 36."
  end

  test "the Vitals page: log one, see the chart and the timeline, delete one", %{
    conn: conn,
    cat: cat
  } do
    {:ok, _} =
      Vitals.log(cat, %{temp_f: 99.6}, date: Date.add(LocalTime.today(), -1), time: ~T[08:00:00])

    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}/vitals")
    view |> element("#vitals-add") |> render_click()

    view
    |> form("#vitals-form",
      v: %{temp: "38.6", pulse: "40", resp: "", time: "07:15", note: "After turnout"}
    )
    |> render_submit()

    assert has_element?(view, "#now-temp_f", "101.5")
    assert has_element?(view, "#now-temp_f.warm", "38.6 °C")
    assert has_element?(view, "#vitals-guide", "Slightly high, not a fever")
    assert has_element?(view, "#vitals-timeline", "not a fever (fever is over 101.5 °F)")
    assert has_element?(view, "#temp-chart svg circle")
    assert has_element?(view, "#vitals-timeline", "Yesterday")
    assert has_element?(view, "#vitals-timeline", "After turnout")

    [newest, older] = Vitals.list(cat.id)
    assert newest.event_time == ~T[07:15:00]
    view |> element("#delete-reading-#{older.id}") |> render_click()
    assert [_] = Vitals.list(cat.id)
  end

  test "the health record lists recent vitals", %{conn: conn, cat: cat} do
    {:ok, _} = Vitals.log(cat, %{temp_f: 100.2, pulse: 38}, time: ~T[09:30:00])
    html = conn |> get(~p"/animals/#{cat.id}/health") |> html_response(200)
    assert html =~ "Vitals (recent)"
    assert html =~ "100.2 °F (37.9 °C)"
  end
end
