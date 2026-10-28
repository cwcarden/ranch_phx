defmodule RanchPhx.Push do
  @moduledoc """
  Phone notifications. A device turns them on from the Notifications page (on an
  iPhone or iPad the app must be on the Home Screen); reminders and tests go to every
  device of that user. The signing keys are made once and kept in the database.
  """
  import Ecto.Query
  require Logger
  alias RanchPhx.Repo
  alias RanchPhx.Push.{Subscription, WebPush}

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
