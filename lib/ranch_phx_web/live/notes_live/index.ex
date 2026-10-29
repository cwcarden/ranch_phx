defmodule RanchPhxWeb.NotesLive.Index do
  @moduledoc """
  An animal's handwritten notes: pages written with the Pencil, by date and topic.
  After a page is saved the AI reads the handwriting into text (shown under the page,
  correctable, and what the search looks through). Pages can be opened and written on
  again; the pen strokes are kept with each one.
  """
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1]
  alias RanchPhx.{Animals, Notes}
  alias RanchPhx.Notes.AI
  alias RanchPhx.Training.Coach
  alias RanchPhx.Accounts.Scope

  @uploads_dir Application.app_dir(:ranch_phx, "priv/static/uploads")

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    animal = Animals.get_animal!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{animal.name}'s notes")
     |> assign(:animal, animal)
     |> assign(:is_superuser, Scope.superuser?(socket.assigns.current_scope))
     |> assign(:ai_on, Coach.configured?())
     |> assign(topic: "all", q: "", viewing: nil, editing_text: false, reading: MapSet.new())
     |> assign(:pending, nil)
     |> assign(:files, %{})
     |> load()
     |> allow_upload(:page,
       accept: ~w(.png .json),
       max_entries: 2,
       max_file_size: 12_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp load(socket) do
    %{animal: a, topic: t, q: q} = socket.assigns
    assign(socket, :notes, Notes.list(a.id, topic: t, q: q))
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(topic: params["topic"] || socket.assigns.topic, q: params["q"] || socket.assigns.q)
     |> load()}
  end

  def handle_event("upload_change", _params, socket), do: {:noreply, socket}

  # The page's details first, then the picture and the strokes.
  def handle_event("note_meta", params, socket) do
    cond do
      not socket.assigns.is_superuser ->
        {:reply, %{ok: false, error: "This account can't add notes."}, socket}

      params["topic"] not in RanchPhx.Notes.Note.topics() ->
        {:reply, %{ok: false, error: "Pick a topic."}, socket}

      true ->
        pending = %{
          id: own_id(socket, params["id"]),
          date: past_date(params["date"]),
          topic: params["topic"],
          title: params["title"] |> to_string() |> String.trim() |> String.slice(0, 120)
        }

        {:reply, %{ok: true}, assign(socket, pending: pending, files: %{})}
    end
  end

  def handle_event("view", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, viewing: Notes.get(socket.assigns.animal.id, id), editing_text: false)}

  def handle_event("close_view", _params, socket), do: {:noreply, assign(socket, viewing: nil)}

  def handle_event("edit_text", _params, socket),
    do: {:noreply, assign(socket, editing_text: true)}

  def handle_event("save_text", %{"text" => text}, socket) do
    with true <- socket.assigns.is_superuser,
         %{} = n <- socket.assigns.viewing,
         {:ok, n} <- Notes.update(n, %{text: String.trim(text)}) do
      {:noreply, socket |> assign(viewing: n, editing_text: false) |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("read_again", _params, socket) do
    case socket.assigns.viewing do
      %{} = n -> {:noreply, read(socket, n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with true <- socket.assigns.is_superuser,
         %{} = n <- Notes.get(socket.assigns.animal.id, id) do
      Notes.delete(n)
      Enum.each([n.page_url, n.strokes_url], &remove/1)
    end

    {:noreply, socket |> assign(viewing: nil) |> load()}
  end

  def handle_progress(:page, entry, socket) do
    if entry.done? do
      kind = if String.ends_with?(entry.client_name, ".json"), do: :strokes, else: :page

      url =
        consume_uploaded_entry(socket, entry, &{:ok, store(socket.assigns.animal, &1.path, kind)})

      socket = update(socket, :files, &Map.put(&1, kind, url))
      %{pending: p, files: f} = socket.assigns

      if p && f[:page] && f[:strokes],
        do: {:noreply, finish(socket, p, f)},
        else: {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp finish(socket, p, f) do
    %{animal: a} = socket.assigns

    attrs = %{
      animal_id: a.id,
      date: p.date,
      topic: p.topic,
      title: blank(p.title),
      page_url: f.page,
      strokes_url: f.strokes
    }

    saved =
      case p.id && Notes.get(a.id, p.id) do
        nil ->
          Notes.create(attrs)

        old ->
          with {:ok, n} <- Notes.update(old, attrs) do
            Enum.each([old.page_url, old.strokes_url], &remove/1)
            {:ok, n}
          end
      end

    socket = assign(socket, pending: nil, files: %{})

    case saved do
      {:ok, n} ->
        socket
        |> load()
        |> assign(viewing: n, editing_text: false)
        |> push_event("note-saved", %{})
        |> put_flash(:info, "Page saved.")
        |> read(n)

      _ ->
        push_event(socket, "note-failed", %{
          message: "Couldn't save that page. Tap Save to try again."
        })
    end
  end

  # The AI reads the handwriting into text, in the background.
  defp read(socket, n) do
    with true <- socket.assigns.ai_on,
         {:ok, png} <- File.read(path(n.page_url)) do
      name = socket.assigns.animal.name

      socket
      |> update(:reading, &MapSet.put(&1, n.id))
      |> start_async({:read, n.id}, fn -> {n.id, AI.transcribe(png, name)} end)
    else
      _ -> socket
    end
  end

  @impl true
  def handle_async({:read, _}, {:ok, {id, {:ok, text}}}, socket) do
    with %{} = n <- Notes.get(socket.assigns.animal.id, id),
         {:ok, n} <- Notes.update(n, %{text: text}) do
      socket = socket |> update(:reading, &MapSet.delete(&1, id)) |> load()

      {:noreply,
       if(match?(%{id: ^id}, socket.assigns.viewing),
         do: assign(socket, :viewing, n),
         else: socket
       )}
    else
      _ -> {:noreply, update(socket, :reading, &MapSet.delete(&1, id))}
    end
  end

  def handle_async({:read, id}, _other, socket) do
    {:noreply,
     socket
     |> update(:reading, &MapSet.delete(&1, id))
     |> put_flash(:error, "The AI couldn't read that page. You can type the text in.")}
  end

  defp store(animal, tmp, kind) do
    dir = Path.join([@uploads_dir, "animals", "#{animal.id}", "notes"])
    File.mkdir_p!(dir)
    ext = if kind == :strokes, do: ".json", else: ".png"
    name = "#{:crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)}#{ext}"
    File.cp!(tmp, Path.join(dir, name))
    "/uploads/animals/#{animal.id}/notes/#{name}"
  end

  defp path("/uploads/" <> rest), do: Path.join(@uploads_dir, rest)
  defp path(_), do: ""

  defp remove("/uploads/animals/" <> rest = url) do
    if String.contains?(rest, "/notes/") and not String.contains?(rest, ".."),
      do: File.rm(path(url))
  end

  defp remove(_), do: :ok

  defp own_id(socket, id) do
    with {n, ""} <- Integer.parse(to_string(id)),
         %{} <- Notes.get(socket.assigns.animal.id, n),
         do: n,
         else: (_ -> nil)
  end

  defp past_date(v) do
    today = RanchPhx.LocalTime.today()

    case Date.from_iso8601(to_string(v)) do
      {:ok, d} -> if Date.compare(d, today) == :gt, do: today, else: d
      _ -> today
    end
  end

  defp blank(""), do: nil
  defp blank(s), do: s

  def snippet(nil), do: nil

  def snippet(text) do
    t = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(t) > 140, do: String.slice(t, 0, 140) <> "…", else: t
  end
end
