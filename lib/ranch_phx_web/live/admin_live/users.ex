defmodule RanchPhxWeb.AdminLive.Users do
  use RanchPhxWeb, :live_view
  alias RanchPhx.Accounts
  alias RanchPhx.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:users, Accounts.list_users())
     |> assign(:new_email, "")
     |> assign(:new_role, "viewer")
     |> assign(:error, nil)}
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
end
