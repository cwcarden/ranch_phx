defmodule RanchPhxWeb.TrainingLive.Index do
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents
  alias RanchPhx.Training
  alias RanchPhx.Training.Book
  alias RanchPhx.Accounts.Scope

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
     |> load_books()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # /training?horse=12 (from a horse's page) opens the form with that horse picked.
    case params do
      %{"horse" => id} -> {:noreply, open_new(socket, %{"animal_id" => id})}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_new", _params, socket), do: {:noreply, open_new(socket, %{})}
  def handle_event("close_new", _params, socket), do: {:noreply, assign(socket, :show_new, false)}

  def handle_event("create_book", %{"book" => params}, socket) do
    if socket.assigns.is_superuser do
      case Training.create_book(params) do
        {:ok, book} ->
          {:noreply, push_navigate(socket, to: ~p"/training/#{book.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, :book_form, to_form(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  defp open_new(socket, params) do
    defaults = %{
      "started_on" => Date.to_iso8601(socket.assigns.today),
      "program_id" => List.first(socket.assigns.programs) |> then(&(&1 && &1.id))
    }

    socket
    |> assign(:show_new, true)
    |> assign(:horses, Training.horses_without_book())
    |> assign(:book_form, to_form(Training.change_book(%Book{}, Map.merge(defaults, params))))
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
