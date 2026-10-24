defmodule RanchPhxWeb.AnimalLive.Index do
  use RanchPhxWeb, :live_view
  alias RanchPhx.Animals
  alias RanchPhx.Animals.Insights
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
     |> assign(:filter_kind, Map.get(params, "kind", socket.assigns.filter_kind))
     |> assign(:filter_status, Map.get(params, "status", socket.assigns.filter_status))
     |> assign(:search, Map.get(params, "search", socket.assigns.search))
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
    animals =
      Animals.list_animals(
        kind: socket.assigns.filter_kind,
        status: socket.assigns.filter_status,
        search: socket.assigns.search
      )

    socket
    |> assign(:animals, animals)
    |> assign(:insights, insights(animals))
  end

  # Weight trend, the care item needing attention, and training this week, per animal.
  defp insights(animals) do
    today = Date.utc_today()
    inputs = animals |> Enum.map(& &1.id) |> Animals.insight_inputs()

    training =
      RanchPhx.Training.list_active_books()
      |> Enum.filter(& &1.horse.animal_id)
      |> Map.new(fn book ->
        {book.horse.animal_id,
         %{
           book_id: book.id,
           week: RanchPhx.Training.week_summary(book.id, today),
           last: book.id |> RanchPhx.Training.last_session() |> then(&(&1 && &1.date))
         }}
      end)

    Map.new(animals, fn a ->
      %{events: events, records: records} = Map.get(inputs, a.id, %{events: [], records: []})

      {a.id,
       %{
         weight: events |> Insights.weights(records) |> Insights.weight_trend(),
         height: events |> Insights.heights(records) |> Insights.trend(),
         care: Insights.care_alert(records, today),
         training: Map.get(training, a.id)
       }}
    end)
  end

  @doc "\"+1.1 lb/day\" with the sign, or nil."
  def per_day(nil), do: nil
  def per_day(n) when n >= 0, do: "+#{:erlang.float_to_binary(n * 1.0, decimals: 1)} lb/day"
  def per_day(n), do: "#{:erlang.float_to_binary(n * 1.0, decimals: 1)} lb/day"

  def days_ago(date, today) do
    case Date.diff(today, date) do
      0 -> "today"
      1 -> "yesterday"
      n when n < 7 -> Calendar.strftime(date, "%a")
      n -> "#{n} days ago"
    end
  end

  def due_short(days) when days < 0, do: "#{-days}d overdue"
  def due_short(0), do: "due today"
  def due_short(days), do: "due in #{days}d"
end
