defmodule RanchPhxWeb.AdminLive.Users do
  use RanchPhxWeb, :live_view
  alias RanchPhx.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:users, Accounts.list_users())
     |> assign(:new_email, "")
     |> assign(:new_role, "viewer")
     |> assign(:error, nil)
     |> assign(:link, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("add_user", %{"email" => email, "role" => role}, socket) do
    case Accounts.admin_create_user(%{"email" => String.trim(email), "role" => role}) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:new_email, "")
         |> assign(:error, nil)
         |> put_flash(:info, "User #{email} added.")}

      {:error, changeset} ->
        msg = changeset.errors |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end) |> Enum.join(", ")
        {:noreply, assign(socket, :error, msg)}
    end
  end

  def handle_event("sign_in_link", %{"id" => id}, socket) do
    user = Enum.find(socket.assigns.users, &("#{&1.id}" == id))

    if user do
      token = Accounts.login_link_token(user)
      {:noreply, assign(socket, :link, %{id: user.id, email: user.email, url: link_url(socket, token)})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_link", _, socket), do: {:noreply, assign(socket, :link, nil)}

  def handle_event("set_role", %{"id" => id, "role" => role}, socket) do
    user = Accounts.get_user!(String.to_integer(id))

    if user.id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "You can't change your own role.")}
    else
      Accounts.update_user_role(user, role)
      {:noreply,
       socket
       |> assign(:users, Accounts.list_users())
       |> put_flash(:info, "Role updated.")}
    end
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(String.to_integer(id))

    if user.id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "You can't delete your own account here.")}
    else
      Accounts.delete_user(user)
      {:noreply,
       socket
       |> assign(:users, Accounts.list_users())
       |> put_flash(:info, "User removed.")}
    end
  end

  # The address the app was opened at (ranch.gimelranch.com), not a configured host.
  defp link_url(socket, token) do
    case socket.host_uri do
      %URI{host: host} = uri when is_binary(host) ->
        local? = host in ["localhost", "127.0.0.1"]
        uri = if local?, do: uri, else: %URI{uri | scheme: "https", port: 443}
        URI.to_string(%URI{uri | path: "/users/log-in/#{token}", query: nil, fragment: nil})

      _ ->
        url(~p"/users/log-in/#{token}")
    end
  end
end
