defmodule RanchPhxWeb.SettingsLive.Index do
  use RanchPhxWeb, :live_view
  alias RanchPhx.Animals
  alias RanchPhx.Animals.Record

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Record Type Settings")
     |> assign(:adding_cat, nil)
     |> assign(:new_label, "")
     |> assign(:error, nil)
     |> load_types()}
  end

  @impl true
  def handle_event("start_add", %{"cat" => cat}, socket) do
    {:noreply, assign(socket, adding_cat: cat, new_label: "", error: nil)}
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, adding_cat: nil, new_label: "", error: nil)}
  end

  def handle_event("update_label", %{"value" => label}, socket) do
    {:noreply, assign(socket, new_label: label, error: nil)}
  end

  def handle_event("save_type", %{"cat" => cat, "label" => label}, socket) do
    label = String.trim(label)

    if label == "" do
      {:noreply, assign(socket, error: "Label cannot be blank.")}
    else
      slug = label
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "_")
        |> String.trim("_")

      case Animals.create_record_type(%{category: cat, slug: slug, label: label, position: 999}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(adding_cat: nil, new_label: "", error: nil)
           |> load_types()}

        {:error, cs} ->
          msg = cs.errors |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end) |> Enum.join(", ")
          {:noreply, assign(socket, error: msg)}
      end
    end
  end

  def handle_event("delete_type", %{"id" => id}, socket) do
    rt = Animals.get_record_type!(String.to_integer(id))
    Animals.delete_record_type(rt)
    {:noreply, load_types(socket)}
  end

  defp load_types(socket) do
    by_cat = Animals.list_record_types_by_category()
    assign(socket, :types_by_cat, by_cat)
  end
end
