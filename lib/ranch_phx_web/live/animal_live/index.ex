defmodule RanchPhxWeb.AnimalLive.Index do
  use RanchPhxWeb, :live_view
  alias RanchPhx.Animals
  alias RanchPhx.Animals.Animal
  alias RanchPhx.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:filter_kind, "")
     |> assign(:filter_status, "")
     |> assign(:search, "")
     |> assign(:show_modal, false)
     |> assign(:changeset, Animals.change_animal(%Animal{}))
     |> assign(:is_superuser, Scope.superuser?(socket.assigns[:current_scope]))
     |> load_animals()}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:filter_kind,   Map.get(params, "kind",   socket.assigns.filter_kind))
     |> assign(:filter_status, Map.get(params, "status", socket.assigns.filter_status))
     |> assign(:search,        Map.get(params, "search", socket.assigns.search))
     |> load_animals()}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter_kind, "")
     |> assign(:filter_status, "")
     |> assign(:search, "")
     |> load_animals()}
  end

  def handle_event("open_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:changeset, Animals.change_animal(%Animal{}))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  def handle_event("save_animal", %{"animal" => params}, socket) do
    case Animals.create_animal(params) do
      {:ok, animal} ->
        {:noreply,
         socket
         |> assign(:show_modal, false)
         |> put_flash(:info, "#{animal.name} added.")
         |> load_animals()}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("toggle_favorite", %{"id" => id}, socket) do
    animal = Animals.get_animal!(id)
    Animals.update_animal(animal, %{is_favorite: !animal.is_favorite})
    {:noreply, load_animals(socket)}
  end

  defp load_animals(socket) do
    animals = Animals.list_animals(
      kind:   socket.assigns.filter_kind,
      status: socket.assigns.filter_status,
      search: socket.assigns.search
    )
    assign(socket, :animals, animals)
  end
end
