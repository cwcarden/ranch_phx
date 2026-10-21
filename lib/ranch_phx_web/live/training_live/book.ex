defmodule RanchPhxWeb.TrainingLive.Book do
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents
  alias RanchPhx.Training
  alias RanchPhx.Training.Session
  alias RanchPhx.Accounts.Scope
  alias RanchPhxWeb.Uploads

  @minute_chips [10, 15, 20, 30, 45]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = Training.get_book!(id)
    offset = if connected?(socket), do: get_connect_params(socket)["tz_offset"], else: nil
    today = Training.today(offset)

    {:ok,
     socket
     |> assign(:page_title, "#{book.horse.name} · Training")
     |> assign(:book, book)
     |> assign(:today, today)
     |> assign(:minute_chips, @minute_chips)
     |> assign(:is_superuser, Scope.superuser?(socket.assigns[:current_scope]))
     |> assign(:errors, [])
     |> assign(:profile_form, nil)
     |> allow_upload(:photo,
       accept: Uploads.image_types(),
       max_entries: 1,
       max_file_size: 20_000_000
     )
     |> reset_form()
     |> load()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("change", %{"session" => params} = payload, socket) do
    {:noreply,
     socket
     |> assign(:params, normalize(params, payload["_target"]))
     |> put_warnings()}
  end

  def handle_event("save", %{"session" => params}, socket) do
    with true <- socket.assigns.is_superuser,
         params =
           normalize(params)
           |> Map.put("book_id", socket.assigns.book.id),
         {:ok, _session} <- Training.save_session(params) do
      {:noreply,
       socket
       |> put_flash(:info, "Session saved")
       |> reset_form(params["date"])
       |> load()}
    else
      false ->
        {:noreply, socket}

      {:error, changeset} ->
        errors =
          Enum.map(changeset.errors, fn {field, {msg, _}} ->
            "#{Phoenix.Naming.humanize(field)} #{msg}"
          end)

        {:noreply, assign(socket, :errors, errors)}
    end
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    if socket.assigns.is_superuser, do: Training.delete_session(socket.assigns.book.id, id)
    {:noreply, load(socket)}
  end

  def handle_event("edit_profile", _params, socket) do
    {:noreply,
     assign(socket, :profile_form, to_form(Training.change_horse(socket.assigns.book.horse)))}
  end

  def handle_event("cancel_profile", _params, socket) do
    {:noreply, assign(socket, :profile_form, nil)}
  end

  def handle_event("validate_profile", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_photo", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("save_profile", %{"horse" => params}, socket) do
    horse = socket.assigns.book.horse

    with true <- socket.assigns.is_superuser,
         {:ok, horse} <- Training.update_horse(horse, Map.delete(params, "animal_id")) do
      [url | _] =
        consume_uploaded_entries(socket, :photo, fn %{path: tmp}, entry ->
          {:ok, Uploads.save_image(tmp, entry.client_name, "training/horses/#{horse.id}")}
        end) ++ [nil]

      if url, do: Training.set_horse_photo(horse, url)

      {:noreply,
       socket
       |> assign(:profile_form, nil)
       |> assign(:book, Training.get_book!(socket.assigns.book.id))
       |> put_flash(
         :info,
         if(url == nil and socket.assigns.uploads.photo.entries != [],
           do: "Saved, but the photo didn't upload. Try again.",
           else: "Profile saved"
         )
       )
       |> load()}
    else
      false -> {:noreply, socket}
      {:error, changeset} -> {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  def handle_event("set_stage", params, socket) do
    if socket.assigns.is_superuser do
      stage_id =
        with %{"id" => id} <- params, {int, ""} <- Integer.parse(id), do: int, else: (_ -> nil)

      {:ok, _} = Training.set_stage_override(socket.assigns.book, stage_id)
      {:noreply, socket |> assign(:book, Training.get_book!(socket.assigns.book.id)) |> load()}
    else
      {:noreply, socket}
    end
  end

  # Unchecking every tag sends only the hidden "" placeholder. Minutes and the date
  # come from a quick-pick button or the typed box, whichever was touched last.
  defp normalize(params, target \\ nil) do
    params =
      Map.update(params, "tags", [], fn tags -> Enum.reject(List.wrap(tags), &(&1 == "")) end)

    params =
      case target do
        ["session", "minute_chip"] -> Map.put(params, "minutes_typed", "")
        ["session", "minutes_typed"] -> Map.delete(params, "minute_chip")
        ["session", "date_chip"] -> Map.put(params, "date_typed", "")
        ["session", "date_typed"] -> Map.delete(params, "date_chip")
        _ -> params
      end

    params
    |> Map.put("minutes", pick(params["minutes_typed"], params["minute_chip"]))
    |> Map.put("date", pick(params["date_typed"], params["date_chip"]))
  end

  defp pick(typed, chip) when typed in [nil, ""], do: chip
  defp pick(typed, _chip), do: typed

  # Keeps the last date used, so several past days can be logged in a row.
  defp reset_form(socket, date \\ nil) do
    date = date || Date.to_iso8601(socket.assigns.today)
    chip? = date in Enum.map(date_chips(socket.assigns.today), &elem(&1, 0))

    socket
    |> assign(:params, %{
      "client_id" => Ecto.UUID.generate(),
      "date" => date,
      "date_chip" => if(chip?, do: date),
      "date_typed" => if(chip?, do: "", else: date),
      "session_type" => nil,
      "minute_chip" => nil,
      "minutes_typed" => "",
      "minutes" => nil,
      "tags" => [],
      "note" => ""
    })
    |> assign(:errors, [])
    |> assign(:warnings, [])
  end

  defp load(socket) do
    %{book: book, today: today} = socket.assigns

    socket
    |> assign(:progress, Training.progress(book, today))
    |> assign(:week, Training.week_summary(book.id, today))
    |> assign(:sessions, Training.list_sessions(book.id))
    |> put_warnings()
  end

  defp put_warnings(socket) do
    %{params: params, progress: progress, week: week} = socket.assigns

    minutes =
      case Integer.parse("#{params["minutes"]}") do
        {m, _} -> m
        :error -> nil
      end

    assign(
      socket,
      :warnings,
      Training.guardrail_warnings(
        progress.stage,
        %{minutes: minutes, session_type: params["session_type"]},
        week
      )
    )
  end

  def sex_label("stallion"), do: "Stud"
  def sex_label("gelding"), do: "Gelding"
  def sex_label("mare"), do: "Mare"
  def sex_label(other), do: other

  def date_chips(today) do
    [{Date.to_iso8601(today), "Today"}, {Date.to_iso8601(Date.add(today, -1)), "Yesterday"}]
  end

  def type_options, do: Session.types()
  def tag_options, do: Session.tags()

  def fmt_date(iso, today) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> fmt_date(date, today)
      _ -> "–"
    end
  end

  def fmt_date(date, today) do
    case Date.diff(today, date) do
      0 -> "Today"
      1 -> "Yesterday"
      _ -> Calendar.strftime(date, "%a %b %-d")
    end
  end
end
