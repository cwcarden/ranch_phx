defmodule RanchPhx.PushTest do
  use RanchPhx.DataCase, async: false
  alias RanchPhx.{Animals, Push}
  alias RanchPhx.Push.{Reminders, WebPush}

  # The device's side of RFC 8291, to check what we send can be read.
  defp decrypt(body, ua_private, ua_public, auth) do
    <<salt::binary-16, _rs::32, idlen::8, as_public::binary-size(idlen), rest::binary>> = body
    shared = :crypto.compute_key(:ecdh, as_public, ua_private, :prime256v1)
    h = &:crypto.mac(:hmac, :sha256, &1, &2)
    prk_key = h.(auth, shared)

    ikm =
      h.(prk_key, "WebPush: info" <> <<0>> <> ua_public <> as_public <> <<1>>)
      |> binary_part(0, 32)

    prk = h.(salt, ikm)
    cek = h.(prk, "Content-Encoding: aes128gcm" <> <<0, 1>>) |> binary_part(0, 16)
    nonce = h.(prk, "Content-Encoding: nonce" <> <<0, 1>>) |> binary_part(0, 12)
    size = byte_size(rest) - 16
    <<cipher::binary-size(size), tag::binary-16>> = rest
    plain = :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, cipher, <<>>, tag, false)
    String.trim_trailing(plain, <<2>>)
  end

  test "a message encrypted for a device can be read by that device" do
    {ua_public, ua_private} = :crypto.generate_key(:ecdh, :prime256v1)
    auth = :crypto.strong_rand_bytes(16)
    body = WebPush.encrypt(~s({"title":"Hi"}), ua_public, auth)
    assert decrypt(body, ua_private, ua_public, auth) == ~s({"title":"Hi"})
  end

  test "encryption matches the worked example in RFC 8291" do
    d = &WebPush.unb64/1

    got =
      WebPush.encrypt(
        "When I grow up, I want to be a watermelon",
        d.(
          "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
        ),
        d.("BTBZMqHH6r4Tts7J_aSIgg"),
        server_keys:
          {d.(
             "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"
           ), d.("yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw")},
        salt: d.("DGv6ra1nlYgDCS1FRnbzlw")
      )

    assert WebPush.b64(got) ==
             "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"
  end

  test "the VAPID signature checks out with the app's public key" do
    {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)

    "vapid t=" <> rest =
      WebPush.vapid_header("https://web.push.apple.com/abc", pub, priv, "https://x")

    [jwt, "k=" <> _] = String.split(rest, ", ")
    [h, c, sig] = String.split(jwt, ".")
    <<r::binary-32, s::binary-32>> = WebPush.unb64(sig)

    int = fn b ->
      b = if :binary.first(b) >= 0x80, do: <<0>> <> b, else: b
      <<0x02, byte_size(b)>> <> b
    end

    seq = int.(r) <> int.(s)
    der = <<0x30, byte_size(seq)>> <> seq
    assert :crypto.verify(:ecdsa, :sha256, h <> "." <> c, der, [pub, :prime256v1])
    assert %{"aud" => "https://web.push.apple.com"} = Jason.decode!(WebPush.unb64(c))
  end

  test "sends to each device; a device that's gone is removed" do
    user = RanchPhx.AccountsFixtures.user_fixture()
    {ua_public, _} = :crypto.generate_key(:ecdh, :prime256v1)

    for {e, _} <- [{"https://push.example/ok", 201}, {"https://push.example/gone", 410}] do
      {:ok, _} =
        Push.subscribe(user, %{
          "endpoint" => e,
          "keys" => %{
            "p256dh" => WebPush.b64(ua_public),
            "auth" => WebPush.b64(:crypto.strong_rand_bytes(16))
          }
        })
    end

    Req.Test.stub(Push, fn conn ->
      assert [<<"vapid t=", _::binary>>] = Plug.Conn.get_req_header(conn, "authorization")
      Plug.Conn.send_resp(conn, if(conn.request_path == "/gone", do: 410, else: 201), "")
    end)

    assert Push.notify(Push.devices(user), %{title: "Test", body: "x", url: "/"}) == 1
    assert [%{endpoint: "https://push.example/ok"}] = Push.devices(user)
    assert Push.first_time?("morning:2026-10-31")
    refute Push.first_time?("morning:2026-10-31")
  end

  test "morning and evening reminders say what's due, or nothing" do
    today = ~D[2026-11-01]
    {:ok, asher} = Animals.create_animal(%{name: "Asher", kind: "horse"})

    {:ok, _} =
      Animals.create_record(%{
        "animal_id" => asher.id,
        "record_type" => "deworming",
        "title" => "Deworming",
        "date" => ~D[2026-10-31],
        "description" => "Panacur PowerPac · daily for 5 days",
        "course_done" => [~D[2026-10-31]]
      })

    {:ok, _} =
      Animals.create_record(%{
        "animal_id" => asher.id,
        "record_type" => "coggins",
        "title" => "Coggins test",
        "date" => ~D[2025-11-02],
        "next_due_date" => ~D[2026-11-02]
      })

    records = Animals.get_animal_with_pedigree!(asher.id).records
    msg = Reminders.morning([{asher, records}], today)
    assert msg.title =~ "2 things"
    assert msg.body =~ "Asher: Deworming, day 2 of 5"
    assert msg.body =~ "Coggins test due tomorrow"

    assert %{title: "Asher's Deworming", body: body} =
             Reminders.evening([{asher, records}], today)

    assert body =~ "Day 2 of 5"
    assert Reminders.morning([{asher, []}], today) == nil
  end

  test "settings choose what's included and when; muted animals are left out" do
    user = RanchPhx.AccountsFixtures.user_fixture()
    {:ok, asher} = Animals.create_animal(%{name: "Asher", kind: "horse"})
    {:ok, ruby} = Animals.create_animal(%{name: "Ruby", kind: "dog"})
    today = ~D[2026-11-01]

    for a <- [asher, ruby] do
      {:ok, _} =
        Animals.create_record(%{
          "animal_id" => a.id,
          "record_type" => "coggins",
          "title" => "Coggins test",
          "date" => ~D[2025-11-06],
          "next_due_date" => ~D[2026-11-06]
        })
    end

    rows = for a <- [asher, ruby], do: {a, Animals.get_animal_with_pedigree!(a.id).records}

    # Due in 5 days: not with the default (1 day ahead), yes with a week ahead.
    assert Reminders.morning(rows, today, Push.settings(user)) == nil
    {:ok, s} = Push.update_settings(user, %{care_days_ahead: 7, muted_animal_ids: [ruby.id]})
    assert %{body: "Asher: Coggins test due in 5 days"} = Reminders.morning(rows, today, s)

    {:ok, s} = Push.update_settings(user, %{care: false})
    assert Reminders.morning(rows, today, s) == nil
    assert {:error, _} = Push.update_settings(user, %{morning_hour: 2})
  end

  test "run sends each person's morning reminder once, at their hour" do
    user = RanchPhx.AccountsFixtures.user_fixture()
    {ua_public, _} = :crypto.generate_key(:ecdh, :prime256v1)

    {:ok, _} =
      Push.subscribe(user, %{
        "endpoint" => "https://push.example/me",
        "keys" => %{
          "p256dh" => WebPush.b64(ua_public),
          "auth" => WebPush.b64(:crypto.strong_rand_bytes(16))
        }
      })

    {:ok, asher} = Animals.create_animal(%{name: "Asher", kind: "horse"})

    {:ok, _} =
      Animals.create_record(%{
        "animal_id" => asher.id,
        "record_type" => "coggins",
        "title" => "Coggins test",
        "date" => ~D[2025-11-01],
        "next_due_date" => ~D[2026-11-01]
      })

    test = self()

    Req.Test.stub(Push, fn conn ->
      send(test, :pushed)
      Plug.Conn.send_resp(conn, 201, "")
    end)

    {:ok, _} = Push.update_settings(user, %{morning_hour: 9})
    Reminders.run(~N[2026-11-01 08:00:00])
    refute_received :pushed
    Reminders.run(~N[2026-11-01 09:10:00])
    assert_received :pushed
    Reminders.run(~N[2026-11-01 09:20:00])
    refute_received :pushed
  end
end
