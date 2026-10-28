defmodule RanchPhxWeb.NotificationsLive.Index do
  @moduledoc "Turn phone notifications on for this device, send a test, see devices."
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1]
  alias RanchPhx.Push

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> assign(:public_key, Push.public_key())
     |> assign(:state, :checking)
     |> assign(:endpoint, nil)
     |> assign(:devices, Push.devices(user))
     |> assign(:settings, Push.settings(user))
     |> assign(:animals, RanchPhx.Animals.list_animals(status: "active"))}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # From the browser: :unsupported, :needs_home_screen, :denied, :off or :on.
  @impl true
  def handle_event("push_status", %{"state" => st} = p, socket)
      when st in ~w(unsupported needs_home_screen denied off on) do
    {:noreply, assign(socket, state: String.to_existing_atom(st), endpoint: p["endpoint"])}
  end

  def handle_event("push_subscribed", sub, socket) do
    user = socket.assigns.current_scope.user

    case Push.subscribe(user, sub) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(state: :on, endpoint: sub["endpoint"], devices: Push.devices(user))
         |> put_flash(:info, "Notifications are on for this device.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't turn them on. Try again.")}
    end
  end

  def handle_event("push_unsubscribed", %{"endpoint" => endpoint}, socket) do
    Push.unsubscribe(endpoint)

    {:noreply,
     assign(socket,
       state: :off,
       endpoint: nil,
       devices: Push.devices(socket.assigns.current_scope.user)
     )}
  end

  # Saved as soon as anything changes.
  def handle_event("save_settings", %{"s" => params}, socket) do
    case Push.update_settings(socket.assigns.current_scope.user, params) do
      {:ok, settings} -> {:noreply, assign(socket, :settings, settings)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't save that.")}
    end
  end

  def handle_event("toggle_mute", %{"id" => id}, socket) do
    id = String.to_integer(id)
    muted = socket.assigns.settings.muted_animal_ids
    muted = if id in muted, do: List.delete(muted, id), else: [id | muted]

    {:ok, settings} =
      Push.update_settings(socket.assigns.current_scope.user, %{muted_animal_ids: muted})

    {:noreply, assign(socket, :settings, settings)}
  end

  # iOS doesn't show a banner for the app you're in, so this one waits: go to the Home
  # Screen or lock the phone and it pops up.
  def handle_event("send_test_later", _params, socket) do
    devices = Push.devices(socket.assigns.current_scope.user)

    Task.start(fn ->
      Process.sleep(:timer.seconds(15))

      Push.notify(devices, %{
        title: "Gimel Ranch",
        body: "Notifications work. This is what a reminder looks like.",
        url: "/notifications",
        tag: "test"
      })
    end)

    {:noreply,
     put_flash(socket, :info, "Sending in 15 seconds. Go to the Home Screen or lock the phone.")}
  end

  def handle_event("send_test", _params, socket) do
    devices = Push.devices(socket.assigns.current_scope.user)

    n =
      Push.notify(devices, %{
        title: "Gimel Ranch",
        body: "Notifications work. Reminders come at 7 a.m. and 6 p.m. when something's due.",
        url: "/",
        tag: "test"
      })

    {:noreply,
     socket
     |> assign(:devices, Push.devices(socket.assigns.current_scope.user))
     |> put_flash(
       if(n > 0, do: :info, else: :error),
       if(n > 0,
         do: "Sent to #{n} #{if n == 1, do: "device", else: "devices"}.",
         else: "Couldn't reach any device. Turn notifications off and on again."
       )
     )}
  end

  def handle_event("remove_device", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case Enum.find(Push.devices(user), &(to_string(&1.id) == id)) do
      nil -> :ok
      d -> Push.unsubscribe(d.endpoint)
    end

    {:noreply, assign(socket, :devices, Push.devices(user))}
  end

  @doc "7 → \"7 a.m.\", 18 → \"6 p.m.\""
  def hour_label(12), do: "noon"
  def hour_label(h) when h < 12, do: "#{h} a.m."
  def hour_label(h), do: "#{h - 12} p.m."
end
