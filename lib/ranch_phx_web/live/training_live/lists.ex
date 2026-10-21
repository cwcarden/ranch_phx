defmodule RanchPhxWeb.TrainingLive.Lists do
  @moduledoc "Edit the activity and tag lists shown on the session log form."
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents
  alias RanchPhx.Training
  alias RanchPhx.Training.{Activity, Tag}
  alias RanchPhx.Accounts.Scope

  @impl true
  def mount(params, _session, socket) do
    back =
      case Integer.parse(params["back"] || "") do
        {id, ""} -> ~p"/training/#{id}"
        _ -> ~p"/training"
      end

    {:ok,
     socket
     |> assign(:page_title, "Customize lists")
     |> assign(:back, back)
     |> assign(:is_superuser, Scope.superuser?(socket.assigns[:current_scope]))
     |> assign(:editing, nil)
     |> assign(:error, nil)
     |> load()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  # Viewers can look but not change the lists.
  def handle_event(_event, _params, %{assigns: %{is_superuser: false}} = socket),
    do: {:noreply, socket}

  def handle_event("add_activity", %{"name" => name}, socket) do
    socket |> result(Training.create_activity(name)) |> reply()
  end

  def handle_event("add_tag", %{"name" => name, "kind" => kind}, socket) do
    socket |> result(Training.create_tag(name, kind)) |> reply()
  end

  def handle_event("edit", %{"type" => type, "id" => id}, socket) do
    {:noreply, socket |> assign(:editing, {type, String.to_integer(id)}) |> assign(:error, nil)}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("rename", %{"type" => type, "item_id" => id} = params, socket) do
    attrs = Map.take(params, ["name", "kind"])
    socket |> result(Training.update_item(get(type, id), attrs)) |> reply()
  end

  def handle_event("toggle_hidden", %{"type" => type, "id" => id}, socket) do
    item = get(type, id)
    socket |> result(Training.update_item(item, %{"archived" => !item.archived})) |> reply()
  end

  def handle_event("move", %{"type" => type, "id" => id, "dir" => dir}, socket) do
    Training.move_item(get(type, id), String.to_integer(dir))
    {:noreply, load(socket)}
  end

  defp get("activity", id), do: RanchPhx.Repo.get!(Activity, id)
  defp get("tag", id), do: RanchPhx.Repo.get!(Tag, id)

  defp result(socket, {:ok, _}),
    do: socket |> assign(:editing, nil) |> assign(:error, nil) |> load()

  defp result(socket, {:error, cs}) do
    msg =
      Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{Phoenix.Naming.humanize(f)} #{m}" end)

    assign(socket, :error, msg)
  end

  defp reply(socket), do: {:noreply, socket}

  defp load(socket) do
    socket
    |> assign(:activities, Training.list_activities(archived: true))
    |> assign(:tags, Training.list_tags(archived: true))
  end

  def kind_label("good"), do: "Good"
  def kind_label("problem"), do: "Problem"
  def kind_label("health"), do: "Health"
end
