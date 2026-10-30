defmodule RanchPhx.VoicePushTest do
  use RanchPhx.DataCase, async: false

  import RanchPhx.AccountsFixtures
  alias RanchPhx.{Animals, Push, Repo, VoiceNotes}
  alias RanchPhx.Push.Subscription

  setup do
    Req.Test.set_req_test_to_shared()
    {:ok, _} = Animals.create_animal(%{name: "Gimels Soldier Cat", barn_name: "Asher", kind: "horse"})
    boss = user_fixture() |> Ecto.Changeset.change(role: "superuser") |> Repo.update!()
    viewer = user_fixture()
    {pub, _} = :crypto.generate_key(:ecdh, :prime256v1)

    for u <- [boss, viewer] do
      Repo.insert!(%Subscription{
        user_id: u.id,
        endpoint: "https://push.example/#{u.id}",
        p256dh: Base.url_encode64(pub, padding: false),
        auth: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      })
    end

    %{boss: boss}
  end

  test "a waiting Siri note buzzes superusers who want it, with the count", %{boss: boss} do
    test_pid = self()

    Req.Test.stub(Push, fn conn ->
      send(test_pid, {:pushed, conn.request_path})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    {:ok, [n1]} = VoiceNotes.create_from_text(boss, "Worked with Asher on his feet")
    Push.send_voice_notes_waiting(n1, n1.text)
    boss_path = "/#{boss.id}"
    assert_received {:pushed, ^boss_path}
    refute_received {:pushed, _}

    Push.update_settings(boss, %{voice_notes: false})
    {:ok, [n2]} = VoiceNotes.create_from_text(boss, "Another one")
    Push.send_voice_notes_waiting(n2, n2.text)
    refute_received {:pushed, _}
  end
end
