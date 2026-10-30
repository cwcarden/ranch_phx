defmodule RanchPhx.Push do
  @moduledoc """
  Phone notifications. A device turns them on from the Notifications page (on an
  iPhone or iPad the app must be on the Home Screen); reminders and tests go to every
  device of that user. The signing keys are made once and kept in the database.
  """
  import Ecto.Query
  require Logger
  alias RanchPhx.Repo
  alias RanchPhx.Push.{Settings, Subscription, WebPush}

  @subject "https://ranch.gimelranch.com"

  # ── Keys ──

  @doc "The app's public key (base64url), for the browser's subscribe call."
  def public_key, do: keys() |> elem(0) |> WebPush.b64()

  defp keys do
    case Repo.one(from k in "push_keys", select: {k.public_key, k.private_key}, limit: 1) do
      {pub, priv} ->
        {WebPush.unb64(pub), WebPush.unb64(priv)}

      nil ->
        {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
        now = DateTime.utc_now(:second)

        Repo.insert_all("push_keys", [
          [
            public_key: WebPush.b64(pub),
            private_key: WebPush.b64(priv),
            inserted_at: now,
            updated_at: now
          ]
        ])

        keys()
    end
  end

  # ── Devices ──

  def subscribe(user, %{"endpoint" => endpoint, "keys" => %{"p256dh" => p, "auth" => a}} = params) do
    attrs = %{user_id: user.id, endpoint: endpoint, p256dh: p, auth: a, device: params["device"]}

    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:user_id, :p256dh, :auth, :device, :updated_at]},
      conflict_target: :endpoint
    )
  end

  def subscribe(_user, _), do: {:error, :bad_subscription}

  def unsubscribe(endpoint),
    do: Repo.delete_all(from s in Subscription, where: s.endpoint == ^endpoint)

  def devices(user),
    do: Repo.all(from s in Subscription, where: s.user_id == ^user.id, order_by: s.inserted_at)

  def all_devices, do: Repo.all(Subscription)

  # ── Choices ──

  @doc "A person's notification settings (the defaults until they change something)."
  def settings(%{id: user_id}),
    do: Repo.get_by(Settings, user_id: user_id) || %Settings{user_id: user_id}

  def update_settings(user, attrs) do
    user |> settings() |> Settings.changeset(attrs) |> Repo.insert_or_update()
  end

  @doc "Everyone with at least one device, with their settings and devices."
  def people do
    Subscription
    |> Repo.all()
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, subs} -> {settings(%{id: user_id}), subs} end)
  end

  # ── Sending ──

  @doc """
  Sends `%{title, body, url}` to each subscription. Devices that are gone (the push
  service says 404 or 410) are removed. Returns how many were delivered.
  """
  def notify(subs, %{title: _} = msg) do
    {pub, priv} = keys()
    payload = Jason.encode!(Map.take(msg, [:title, :body, :url, :tag]))

    Enum.count(subs, fn s ->
      body = WebPush.encrypt(payload, WebPush.unb64(s.p256dh), WebPush.unb64(s.auth))

      req =
        Req.new(
          [
            url: s.endpoint,
            method: :post,
            body: body,
            headers: [
              {"content-encoding", "aes128gcm"},
              {"content-type", "application/octet-stream"},
              {"ttl", "43200"},
              {"urgency", "normal"},
              {"authorization", WebPush.vapid_header(s.endpoint, pub, priv, @subject)}
            ],
            retry: false
          ] ++ Application.get_env(:ranch_phx, :push_req_options, [])
        )

      case Req.request(req) do
        {:ok, %{status: st}} when st in 200..299 ->
          true

        {:ok, %{status: st}} when st in [404, 410] ->
          Repo.delete(s)
          false

        other ->
          Logger.warning(
            "Push to #{URI.parse(s.endpoint).host} failed: #{inspect(other, limit: 5)}"
          )

          false
      end
    end)
  end

  @doc """
  Tells superusers' devices that Siri notes are waiting to be checked (one
  notification that updates, rather than a pile). Runs in the background so Siri's
  reply isn't held up.
  """
  def voice_notes_waiting(%{text: text} = note) do
    if Application.get_env(:ranch_phx, :voice_push, true) do
      Task.start(fn -> send_voice_notes_waiting(note, text) end)
    end

    :ok
  end

  @doc false
  def send_voice_notes_waiting(note, text) do
    waiting = RanchPhx.VoiceNotes.count_pending()
    animal = note |> RanchPhx.Repo.preload(:animal) |> Map.get(:animal)
    who = if animal, do: RanchPhx.Animals.Animal.display_name(animal) <> ": ", else: ""
    said = if String.length(text) > 90, do: String.slice(text, 0, 87) <> "…", else: text

    msg = %{
      title: if(waiting > 1, do: "#{waiting} Siri notes to check", else: "Siri note to check"),
      body: "#{who}“#{said}”",
      url: "/voice",
      tag: "voice-notes"
    }

    for {settings, subs} <- people(),
        settings.voice_notes,
        superuser?(settings.user_id) do
      notify(subs, msg)
    end

    :ok
  rescue
    e -> Logger.warning("Siri note push failed: #{Exception.message(e)}")
  end

  defp superuser?(user_id) do
    case RanchPhx.Repo.get(RanchPhx.Accounts.User, user_id) do
      nil -> false
      user -> RanchPhx.Accounts.Scope.superuser?(RanchPhx.Accounts.Scope.for_user(user))
    end
  end

  @doc "When this person's last morning or evening reminder went out, or nil."
  def last_sent(%{id: user_id}) do
    Repo.one(
      from p in "push_sent",
        where: like(p.key, ^"morning:#{user_id}:%") or like(p.key, ^"evening:#{user_id}:%"),
        order_by: [desc: p.inserted_at],
        select: {p.key, p.inserted_at},
        limit: 1
    )
  end

  @doc "Marks `key` as sent; true the first time only (so a reminder goes out once)."
  def first_time?(key) do
    {n, _} =
      Repo.insert_all("push_sent", [[key: key, inserted_at: DateTime.utc_now(:second)]],
        on_conflict: :nothing,
        conflict_target: :key
      )

    n == 1
  end
end
