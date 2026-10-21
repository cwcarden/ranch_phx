defmodule RanchPhxWeb.TrainingLive.Index do
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents
  alias RanchPhx.Training
  alias RanchPhx.Training.{Book, Horse}
  alias RanchPhx.Accounts.Scope
  alias RanchPhxWeb.Uploads

  @impl true
  def mount(_params, _session, socket) do
    today = Training.today(connect_offset(socket))

    {:ok,
     socket
     |> assign(:page_title, "Training")
     |> assign(:today, today)
     |> assign(:is_superuser, Scope.superuser?(socket.assigns[:current_scope]))
     |> assign(:programs, Training.list_programs())
     |> assign(:show_new, false)
     |> allow_upload(:photo,
       accept: Uploads.image_types(),
       max_entries: 1,
       max_file_size: 20_000_000
     )
     |> load_books()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # /training?horse=12 (from a ranch horse's page) opens the form with that horse picked.
    case params do
      %{"horse" => id} -> {:noreply, open_new(socket, %{"animal_id" => id})}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_new", _params, socket), do: {:noreply, open_new(socket, %{})}
  def handle_event("close_new", _params, socket), do: {:noreply, assign(socket, :show_new, false)}

  def handle_event("set_source", %{"source" => source}, socket) when source in ~w(ranch other) do
    {:noreply, assign(socket, :source, source)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("create_book", params, socket) do
    if socket.assigns.is_superuser do
      book_params = Map.get(params, "book", %{})

      horse_params =
        case socket.assigns.source do
          "ranch" -> %{"animal_id" => book_params["animal_id"]}
          "other" -> Map.get(params, "horse", %{})
        end

      case Training.start_book(horse_params, Map.delete(book_params, "animal_id")) do
        {:ok, book} ->
          save_photo(socket, book.horse_id)
          {:noreply, push_navigate(socket, to: ~p"/training/#{book.id}")}

        {:error, :horse, changeset} ->
          {:noreply, assign(socket, :horse_form, to_form(changeset))}

        {:error, :book, changeset} ->
          {:noreply, assign(socket, :book_form, to_form(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_photo", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  defp save_photo(socket, horse_id) do
    [url | _] =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp}, entry ->
        {:ok, Uploads.save_image(tmp, entry.client_name, "training/horses/#{horse_id}")}
      end) ++ [nil]

    if url, do: Training.set_horse_photo(Training.get_horse!(horse_id), url)
  end

  defp open_new(socket, params) do
    ranch_horses = Training.ranch_horses_without_book()

    defaults = %{
      "started_on" => Date.to_iso8601(socket.assigns.today),
      "program_id" => List.first(socket.assigns.programs) |> then(&(&1 && &1.id))
    }

    socket
    |> assign(:show_new, true)
    |> assign(:ranch_horses, ranch_horses)
    |> assign(:source, if(ranch_horses == [], do: "other", else: "ranch"))
    |> assign(:selected_animal_id, params["animal_id"])
    |> assign(:book_form, to_form(Training.change_book(%Book{}, defaults)))
    |> assign(:horse_form, to_form(Training.change_horse(%Horse{})))
  end

  defp load_books(socket) do
    books = Training.list_active_books()
    last = Training.last_session_dates(Enum.map(books, & &1.id))
    today = socket.assigns.today

    cards =
      Enum.map(books, fn book ->
        %{
          book: book,
          progress: Training.progress(book, today),
          week: Training.week_summary(book.id, today),
          last: last[book.id]
        }
      end)

    assign(socket, :cards, cards)
  end

  defp connect_offset(socket) do
    if connected?(socket), do: get_connect_params(socket)["tz_offset"], else: nil
  end

  def days_since(nil, _today), do: "No sessions yet"

  def days_since(date, today) do
    case Date.diff(today, date) do
      0 -> "Last session today"
      1 -> "Last session yesterday"
      n -> "Last session #{n} days ago"
    end
  end
end
