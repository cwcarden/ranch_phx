defmodule RanchPhxWeb.NotificationsLiveTest do
  use RanchPhxWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias RanchPhx.Push
  alias RanchPhx.Push.WebPush

  setup :register_and_log_in_user

  test "turn on for this device, send a test, turn off", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/notifications")
    assert render(view) =~ "Checking"

    render_hook(view, "push_status", %{"state" => "off"})
    assert has_element?(view, "#push-on")

    {ua_public, _} = :crypto.generate_key(:ecdh, :prime256v1)

    render_hook(view, "push_subscribed", %{
      "endpoint" => "https://web.push.apple.com/device1",
      "keys" => %{
        "p256dh" => WebPush.b64(ua_public),
        "auth" => WebPush.b64(:crypto.strong_rand_bytes(16))
      },
      "device" => "iPhone"
    })

    assert has_element?(view, "#send-test")
    assert has_element?(view, "#push-devices", "iPhone")

    Req.Test.stub(Push, fn conn -> Plug.Conn.send_resp(conn, 201, "") end)
    view |> element("#send-test") |> render_click()
    assert has_element?(view, "#toast-info", "Sent to 1 device")

    render_hook(view, "push_unsubscribed", %{"endpoint" => "https://web.push.apple.com/device1"})
    assert Push.devices(user) == []
  end

  test "iPhone in Safari: explains adding to the Home Screen", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/notifications")
    render_hook(view, "push_status", %{"state" => "needs_home_screen"})
    assert render(view) =~ "Add to Home Screen"
  end

  test "change when and what, and mute an animal", %{conn: conn, user: user} do
    {:ok, asher} = RanchPhx.Animals.create_animal(%{name: "Asher", kind: "horse"})
    {:ok, view, _} = live(conn, ~p"/notifications")

    view
    |> form("#settings-form", s: %{morning_hour: "6", care_days_ahead: "7", evening_on: "false"})
    |> render_change()

    s = Push.settings(user)
    assert s.morning_hour == 6 and s.care_days_ahead == 7 and s.evening_on == false

    view |> element("#mute-#{asher.id}") |> render_click()
    assert Push.settings(user).muted_animal_ids == [asher.id]
    assert has_element?(view, "#mute-#{asher.id}.off")
  end
end
