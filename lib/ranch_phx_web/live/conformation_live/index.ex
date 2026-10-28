defmodule RanchPhxWeb.ConformationLive.Index do
  @moduledoc """
  Conformation evaluations, for the ranch's horses and for prospects. Take or choose a
  side photo, place the dots (or let the AI place them, then fix them with the Pencil),
  and save. Opening one shows what the numbers mean, the AI's review (what's good, what
  to watch, best suited for) and questions you ask about the horse.

  `/conformation?animal=ID` shows one horse's evaluations and starts new ones for him.
  """
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1, coach_answer: 1]
  alias RanchPhx.{Animals, Conformations}
  alias RanchPhx.Conformations.AI
  alias RanchPhx.Training.Coach
  alias RanchPhx.Accounts.Scope

  @uploads_dir Application.app_dir(:ranch_phx, "priv/static/uploads")

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Conformation")
     |> assign(:is_superuser, Scope.superuser?(socket.assigns.current_scope))
     |> assign(:ai_on, Coach.configured?())
     |> assign(
       :horses,
       Animals.list_animals(status: "active") |> Enum.filter(&(&1.kind == "horse"))
     )
     |> assign(:animal, nil)
     |> assign(:who, "prospect")
     |> assign(:prospect, "")
     |> assign(:viewing, nil)
     |> assign(:pending, nil)
     |> assign(:files, %{})
     |> assign(:busy, nil)
     |> assign(:ai_error, nil)
     |> allow_upload(:conf,
       accept: ~w(.jpg .jpeg),
       max_entries: 2,
       max_file_size: 15_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    animal =
      with id when is_binary(id) <- params["animal"],
           {n, ""} <- Integer.parse(id),
           %{} = a <- Enum.find(socket.assigns.horses, &(&1.id == n)) do
        a
      else
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(:animal, animal)
     |> assign(:who, if(animal, do: "animal:#{animal.id}", else: socket.assigns.who))
     |> load()}
  end

  defp load(socket) do
    animal = socket.assigns.animal
    assign(socket, :evaluations, Conformations.list(animal_id: animal && animal.id))
  end

  # ── Who it's of ──
  @impl true
  def handle_event("who", params, socket) do
    {:noreply,
     socket
     |> assign(:who, params["who"] || socket.assigns.who)
     |> assign(:prospect, params["prospect"] || socket.assigns.prospect)}
  end

  def handle_event("upload_change", _params, socket), do: {:noreply, socket}

  # ── Measuring ──
  # The numbers first (worked out on the device from the dots), then the photos.
  def handle_event("conf_measured", params, socket) do
    num = fn k -> number(params[k]) end

    nums = %{
      shoulder: num.("shoulder"),
      hip: num.("hip"),
      uphill: num.("uphill"),
      length_ratio: ratio(params["length_ratio"]),
      neck_ratio: ratio(params["neck_ratio"]),
      thirds: thirds(params["thirds"])
    }

    existing = own(socket, params["event_id"])

    cond do
      not socket.assigns.is_superuser ->
        {:reply, %{ok: false}, socket}

      is_nil(nums.shoulder) or is_nil(nums.hip) or is_nil(nums.uphill) ->
        {:reply, %{ok: false}, socket}

      true ->
        pending = %{
          id: existing && existing.id,
          nums: nums,
          date: past_date(params["date"]),
          note: params["note"] |> to_string() |> String.trim() |> String.slice(0, 1000),
          points: params["points"] || %{},
          with_original: params["with_original"] == true
        }

        {:reply, %{ok: true}, assign(socket, pending: pending, files: %{})}
    end
  end

  # ── AI: place the dots ──
  def handle_event("ai_points", %{"image" => image}, socket) when is_binary(image) do
    if socket.assigns.is_superuser and socket.assigns.ai_on do
      {:noreply, start_async(socket, :ai_points, fn -> AI.place(image) end)}
    else
      {:noreply,
       push_event(socket, "ai-points", %{
         error: "The AI isn't set up here. Place the dots yourself."
       })}
    end
  end

  # ── Looking at one ──
  def handle_event("view", %{"id" => id}, socket),
    do: {:noreply, assign(socket, viewing: own(socket, id), ai_error: nil)}

  def handle_event("close_view", _params, socket), do: {:noreply, assign(socket, :viewing, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    with true <- socket.assigns.is_superuser, %{} = e <- own(socket, id) do
      Conformations.delete(e)
      Enum.each([e.photo_url, e.original_url], &remove/1)
    end

    {:noreply, socket |> assign(:viewing, nil) |> load()}
  end

  def handle_event("review", _params, socket) do
    case {socket.assigns.viewing, socket.assigns.busy} do
      {%{} = e, nil} ->
        today = RanchPhx.LocalTime.today()
        age = age_months(e, today)

        {:noreply,
         socket
         |> assign(busy: :review, ai_error: nil)
         |> start_async(:review, fn -> {e.id, AI.review(e, age, today)} end)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("ask", %{"question" => q}, socket) do
    case {socket.assigns.viewing, socket.assigns.busy, String.trim(q)} do
      {%{} = e, nil, q} when q != "" ->
        today = RanchPhx.LocalTime.today()
        age = age_months(e, today)

        {:noreply,
         socket
         |> assign(busy: {:ask, q}, ai_error: nil)
         |> start_async(:ask, fn -> {e.id, q, AI.ask(e, age, q, today)} end)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_chat", _params, socket) do
    with %{} = e <- socket.assigns.viewing, {:ok, e} <- Conformations.update(e, %{ai_chat: []}) do
      {:noreply, socket |> assign(:viewing, Conformations.get(e.id)) |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:ai_points, {:ok, {:ok, %{points: points, note: note}}}, socket),
    do: {:noreply, push_event(socket, "ai-points", %{points: points, note: note})}

  def handle_async(:ai_points, {:ok, {:error, reason}}, socket),
    do: {:noreply, push_event(socket, "ai-points", %{error: Coach.error_message(reason)})}

  def handle_async(:ai_points, {:exit, _}, socket),
    do:
      {:noreply,
       push_event(socket, "ai-points", %{
         error: "The AI couldn't place the dots. Place them yourself."
       })}

  def handle_async(:review, {:ok, {id, {:ok, text}}}, socket) do
    with %{} = e <- Conformations.get(id),
         {:ok, _} <- Conformations.update(e, %{ai_notes: text}) do
      {:noreply, socket |> assign(busy: nil) |> refresh_view(id)}
    else
      _ -> {:noreply, assign(socket, busy: nil)}
    end
  end

  def handle_async(:review, {:ok, {_id, {:error, reason}}}, socket),
    do: {:noreply, assign(socket, busy: nil, ai_error: Coach.error_message(reason))}

  def handle_async(:review, {:exit, _}, socket),
    do: {:noreply, assign(socket, busy: nil, ai_error: "Something went wrong. Try again.")}

  def handle_async(:ask, {:ok, {id, q, {:ok, answer}}}, socket) do
    with %{} = e <- Conformations.get(id),
         {:ok, _} <-
           Conformations.update(e, %{ai_chat: (e.ai_chat || []) ++ [%{"q" => q, "a" => answer}]}) do
      {:noreply, socket |> assign(busy: nil) |> refresh_view(id)}
    else
      _ -> {:noreply, assign(socket, busy: nil)}
    end
  end

  def handle_async(:ask, {:ok, {_id, _q, {:error, reason}}}, socket),
    do: {:noreply, assign(socket, busy: nil, ai_error: Coach.error_message(reason))}

  def handle_async(:ask, {:exit, _}, socket),
    do: {:noreply, assign(socket, busy: nil, ai_error: "Something went wrong. Try again.")}

  defp refresh_view(socket, id) do
    socket = load(socket)

    if socket.assigns.viewing && socket.assigns.viewing.id == id,
      do: assign(socket, :viewing, Conformations.get(id)),
      else: socket
  end

  # ── Photos in ──
  def handle_progress(:conf, entry, socket) do
    if entry.done? do
      url = consume_uploaded_entry(socket, entry, &{:ok, store(&1.path)})
      kind = if String.starts_with?(entry.client_name, "original"), do: :original, else: :marked
      socket = update(socket, :files, &Map.put(&1, kind, url))
      %{pending: p, files: files} = socket.assigns

      if p && files[:marked] && (files[:original] || !p.with_original),
        do: {:noreply, finish(socket, p, files)},
        else: {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp finish(socket, p, files) do
    existing = p.id && Conformations.get(p.id)

    attrs =
      p.nums
      |> Map.merge(%{
        date: p.date,
        note: blank(p.note),
        points: p.points,
        photo_url: files[:marked]
      })
      |> then(fn a ->
        if files[:original], do: Map.put(a, :original_url, files[:original]), else: a
      end)

    saved =
      case existing do
        nil ->
          Conformations.create(Map.merge(attrs, who_attrs(socket)))

        e ->
          # New lines: the old marked-up photo goes, and the AI's old review with it.
          with {:ok, e2} <- Conformations.update(e, Map.merge(attrs, %{ai_notes: nil})) do
            if e.photo_url != e2.photo_url, do: remove(e.photo_url)
            {:ok, e2}
          end
      end

    socket = assign(socket, pending: nil, files: %{})

    case saved do
      {:ok, e} ->
        socket
        |> load()
        |> assign(:viewing, Conformations.get(e.id))
        |> push_event("hoof-saved", %{})
        |> put_flash(:info, "Saved. Tap AI review for what's good and what to watch.")

      {:error, %Ecto.Changeset{} = cs} ->
        msg = cs.errors |> Keyword.values() |> Enum.map_join(", ", &elem(&1, 0))
        push_event(socket, "hoof-failed", %{message: "Couldn't save: #{msg}."})

      _ ->
        push_event(socket, "hoof-failed", %{
          message: "Couldn't save that one. Tap Save to try again."
        })
    end
  end

  defp who_attrs(socket) do
    case socket.assigns.who do
      "animal:" <> id ->
        case Integer.parse(id) do
          {n, ""} ->
            if Enum.any?(socket.assigns.horses, &(&1.id == n)), do: %{animal_id: n}, else: %{}

          _ ->
            %{}
        end

      _ ->
        name = String.trim(socket.assigns.prospect)
        %{name: if(name == "", do: "Prospect", else: name)}
    end
  end

  defp store(tmp) do
    dir = Path.join(@uploads_dir, "conformation")
    File.mkdir_p!(dir)
    name = "#{:crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)}.jpg"
    File.cp!(tmp, Path.join(dir, name))
    "/uploads/conformation/#{name}"
  end

  defp remove("/uploads/conformation/" <> rest) do
    if not String.contains?(rest, ".."),
      do: File.rm(Path.join([@uploads_dir, "conformation", rest]))
  end

  defp remove(_), do: :ok

  defp own(socket, id) do
    with {n, ""} <- Integer.parse(to_string(id)),
         %{} = e <- Conformations.get(n),
         true <- is_nil(socket.assigns.animal) or e.animal_id == socket.assigns.animal.id do
      e
    else
      _ -> nil
    end
  end

  def age_months(%{animal: %{birth_date: %Date{} = b}}, today),
    do: max(0, (today.year - b.year) * 12 + today.month - b.month)

  def age_months(_, _), do: nil

  defp past_date(v) do
    today = RanchPhx.LocalTime.today()

    case Date.from_iso8601(to_string(v)) do
      {:ok, d} -> if Date.compare(d, today) == :gt, do: today, else: d
      _ -> today
    end
  end

  defp blank(""), do: nil
  defp blank(s), do: s

  defp number(n) when is_number(n), do: Float.round(n * 1.0, 1)

  defp number(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> Float.round(f, 1)
      :error -> nil
    end
  end

  defp number(_), do: nil

  defp ratio(n) when is_number(n) and n > 0 and n < 5, do: Float.round(n * 1.0, 2)
  defp ratio(_), do: nil

  defp thirds([a, b, c]) when is_integer(a) and is_integer(b) and is_integer(c), do: [a, b, c]
  defp thirds(_), do: nil
end
