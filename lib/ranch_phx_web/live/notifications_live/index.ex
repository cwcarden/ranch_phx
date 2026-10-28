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
     |> assign(:devices, Push.devices(user))}
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
end
