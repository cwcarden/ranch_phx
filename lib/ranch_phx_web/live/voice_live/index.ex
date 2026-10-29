defmodule RanchPhxWeb.VoiceLive.Index do
  @moduledoc """
  Siri voice log: what was said with the "Ranch log" Shortcut, waiting to be checked
  and saved as records, plus setting up the Shortcut (its key and the steps).
  """
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1]
  alias RanchPhx.{Accounts, Animals, VoiceNotes}
  alias RanchPhx.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: VoiceNotes.subscribe()
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Siri voice log")
     |> assign(:is_superuser, Scope.superuser?(socket.assigns.current_scope))
     |> assign(:new_key, nil)
     |> assign(:key_made, Accounts.api_token_created_at(user))
     |> assign(:animals, Animals.list_animals(status: "active"))
     |> load()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:voice_notes_changed, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("set_animal", %{"note" => id, "animal" => animal_id}, socket) do
    with true <- socket.assigns.is_superuser,
         %{} = note <- VoiceNotes.get(id) do
      VoiceNotes.set_animal(note, animal_id)
    end

    {:noreply, load(socket)}
  end

  def handle_event("dismiss", %{"note" => id}, socket) do
    with true <- socket.assigns.is_superuser,
         %{} = note <- VoiceNotes.get(id) do
      VoiceNotes.mark(note, "dismissed")
    end

    {:noreply, load(socket)}
  end

  def handle_event("make_key", _params, socket) do
    if socket.assigns.is_superuser do
      user = socket.assigns.current_scope.user
      key = Accounts.create_api_token(user)

      {:noreply, assign(socket, new_key: key, key_made: Accounts.api_token_created_at(user))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("turn_off_key", _params, socket) do
    Accounts.delete_api_token(socket.assigns.current_scope.user)
    {:noreply, assign(socket, new_key: nil, key_made: nil)}
  end

  defp load(socket) do
    notes = VoiceNotes.list_pending()

    books =
      notes
      |> Enum.map(& &1.animal_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Map.new(fn id -> {id, RanchPhx.Training.active_book_for_animal(id)} end)
      |> Map.reject(fn {_, b} -> is_nil(b) end)
      |> Map.new(fn {id, b} -> {id, b.id} end)

    assign(socket, notes: notes, books: books)
  end

  @doc false
  # Sounds like a training session rather than vet/farrier care.
  def training?(text) do
    t = String.downcase(text || "")

    Regex.match?(
      ~r/\b(train|trained|training|worked (with|on)|round ?pen|lung|longe|saddl|sack|groundwork|ground work|ponied|ponying|tied|tie him|lead|picking up|pick up|feet|foot|desensitiz|spray bottle|bridle|ride|rode|riding|backed|trailer|load)/,
      t
    ) and
      not Regex.match?(~r/\b(vaccin|shot|deworm|panacur|quest|coggins|vet|farrier|trim|shod|shoes|float|dental|bute|banamine)/, t)
  end

  @doc "\"Today 3:12 PM\", \"Yesterday 7:05 AM\" or \"Oct 20, 7:05 AM\", in ranch time."
  def said_at(%DateTime{} = dt) do
    local = DateTime.add(dt, offset_seconds(dt), :second)
    today = DateTime.add(DateTime.utc_now(), offset_seconds(DateTime.utc_now()), :second)
    time = Calendar.strftime(local, "%-I:%M %p")

    case Date.diff(DateTime.to_date(today), DateTime.to_date(local)) do
      0 -> "Today #{time}"
      1 -> "Yesterday #{time}"
      _ -> Calendar.strftime(local, "%b %-d, ") <> time
    end
  end

  @doc "The day in ranch time, like \"Oct 24, 2026\"."
  def local_day(%DateTime{} = dt),
    do: dt |> DateTime.add(offset_seconds(dt), :second) |> Calendar.strftime("%b %-d, %Y")

  # US Central: daylight time from the second Sunday of March to the first Sunday of November.
  defp offset_seconds(%DateTime{} = dt) do
    y = dt.year
    start = nth_sunday(y, 3, 2) |> DateTime.new!(~T[08:00:00], "Etc/UTC")
    stop = nth_sunday(y, 11, 1) |> DateTime.new!(~T[07:00:00], "Etc/UTC")
    dst? = DateTime.compare(dt, start) != :lt and DateTime.compare(dt, stop) == :lt
    if dst?, do: -5 * 3600, else: -6 * 3600
  end

  defp nth_sunday(year, month, n) do
    first = Date.new!(year, month, 1)
    offset = rem(7 - Date.day_of_week(first) + 7, 7)
    Date.add(first, offset + (n - 1) * 7)
  end
end
