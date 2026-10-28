defmodule RanchPhxWeb.HoofLive.Index do
  @moduledoc """
  Hoof measurements from a photo. Side view: tap along the ground, the toe wall and
  (optionally) the pastern for the angles. Sole view: tap the toe, heels, widest part
  and frog tip for the balance. The numbers are worked out on the device; the marked-up
  photo and the numbers are saved as a "hoof" timeline event, with a plain-English summary.
  """
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1, coach_answer: 1]
  alias RanchPhx.Animals
  alias RanchPhx.Animals.{Hooves, HoofAI}
  alias RanchPhx.Training.Coach
  alias RanchPhx.Accounts.Scope

  @uploads_dir Application.app_dir(:ranch_phx, "priv/static/uploads")

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    animal = Animals.get_animal_with_pedigree!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{animal.name}'s hooves")
     |> assign(:animal, animal)
     |> assign(:is_superuser, Scope.superuser?(socket.assigns.current_scope))
     |> assign(:foot, "LF")
     |> assign(:view, "side")
     |> assign(:pending, nil)
     |> assign(:error, nil)
     |> assign(:viewing, nil)
     |> assign(:ai_on, Coach.configured?())
     |> assign(:notes, nil)
     |> assign(:notes_loading, false)
     |> load()
     |> allow_upload(:hoof,
       accept: ~w(.jpg .jpeg),
       max_entries: 1,
       max_file_size: 15_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    foot = if params["foot"] in Enum.map(Hooves.feet(), &elem(&1, 0)), do: params["foot"]
    {:noreply, if(foot, do: assign(socket, :foot, foot), else: socket)}
  end

  @impl true
  def handle_event("select_foot", %{"foot" => foot}, socket) do
    if foot in Enum.map(Hooves.feet(), &elem(&1, 0)),
      do: {:noreply, assign(socket, :foot, foot)},
      else: {:noreply, socket}
  end

  def handle_event("select_view", %{"view" => view}, socket) when view in ["side", "sole"],
    do: {:noreply, assign(socket, :view, view)}

  def handle_event("upload_change", _params, socket), do: {:noreply, socket}

  # The measuring screen sends the numbers first, then the marked-up photo.
  def handle_event("hoof_measured", %{"view" => "sole"} = params, socket) do
    foot = params["foot"]

    nums =
      ~w(toe_share sides heels frog)
      |> Map.new(&{&1, number(params[&1])})
      |> Map.put("ratio", ratio(params["ratio"]))

    cond do
      not socket.assigns.is_superuser ->
        {:reply, %{ok: false}, socket}

      foot not in Enum.map(Hooves.feet(), &elem(&1, 0)) or is_nil(nums["toe_share"]) or
        nums["toe_share"] <= 0 or nums["toe_share"] >= 100 ->
        {:reply, %{ok: false},
         assign(socket, :error, "Those dots didn't make a foot. Try again.")}

      true ->
        pending = %{
          view: "sole",
          foot: foot,
          nums: nums,
          date: past_date(params["date"]),
          note: params["note"] |> to_string() |> String.trim() |> String.slice(0, 500),
          points: params["points"]
        }

        {:reply, %{ok: true}, assign(socket, pending: pending, error: nil)}
    end
  end

  def handle_event("hoof_measured", params, socket) do
    toe = number(params["toe"])
    pastern = number(params["pastern"])
    foot = params["foot"]

    date = past_date(params["date"])

    cond do
      not socket.assigns.is_superuser ->
        {:reply, %{ok: false}, socket}

      foot not in Enum.map(Hooves.feet(), &elem(&1, 0)) or is_nil(toe) or toe <= 0 or toe >= 90 ->
        {:reply, %{ok: false},
         assign(socket, :error, "Those lines didn't make an angle. Try again.")}

      true ->
        pending = %{
          foot: foot,
          toe: toe,
          pastern: if(is_number(pastern) and pastern > 0 and pastern < 90, do: pastern),
          date: date,
          note: params["note"] |> to_string() |> String.trim() |> String.slice(0, 500),
          points: params["points"]
        }

        {:reply, %{ok: true}, assign(socket, pending: pending, error: nil)}
    end
  end

  def handle_event("farrier_notes", _params, socket) do
    %{animal: animal, measurements: ms, notes_loading: busy?} = socket.assigns

    if busy? do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(notes_loading: true, notes: nil)
       |> start_async(:notes, fn -> HoofAI.notes(animal, ms, Date.utc_today()) end)}
    end
  end

  def handle_event("view", %{"id" => id}, socket) do
    %{measurements: ms, soles: soles} = socket.assigns
    {:noreply, assign(socket, :viewing, Enum.find(ms ++ soles, &(to_string(&1.id) == id)))}
  end

  def handle_event("close_view", _params, socket), do: {:noreply, assign(socket, :viewing, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    with true <- socket.assigns.is_superuser,
         %{} = event <-
           Enum.find(socket.assigns.animal.timeline_events, &(to_string(&1.id) == id)),
         "hoof" <- event.event_type do
      Animals.delete_event(event)
    end

    {:noreply, socket |> assign(:viewing, nil) |> reload()}
  end

  def handle_progress(:hoof, entry, socket) do
    if entry.done? do
      %{animal: animal, pending: pending} = socket.assigns

      url =
        consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
          dir = Path.join([@uploads_dir, "animals", "#{animal.id}", "hooves"])
          File.mkdir_p!(dir)
          name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}.jpg"
          File.cp!(tmp, Path.join(dir, name))
          {:ok, "/uploads/animals/#{animal.id}/hooves/#{name}"}
        end)

      saved = pending && Animals.create_event(event_attrs(animal, pending, url))

      case saved do
        {:ok, event} ->
          socket = socket |> assign(:pending, nil) |> reload()
          %{measurements: ms, soles: soles} = socket.assigns

          {:noreply,
           socket
           |> assign(:viewing, Enum.find(ms ++ soles, &(&1.id == event.id)))
           |> push_event("hoof-saved", %{})
           |> put_flash(:info, saved_message(pending))}

        _ ->
          {:noreply,
           socket
           |> assign(:pending, nil)
           |> push_event("hoof-failed", %{
             message: "Couldn't save that one. Tap Save to try again."
           })}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:notes, {:ok, {:ok, text}}, socket),
    do: {:noreply, assign(socket, notes: {:ok, text}, notes_loading: false)}

  def handle_async(:notes, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       assign(socket, notes: {:error, Coach.error_message(reason)}, notes_loading: false)}

  def handle_async(:notes, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket, notes: {:error, "Something went wrong. Try again."}, notes_loading: false)}

  defp event_attrs(animal, %{view: "sole"} = p, url) do
    n = p.nums
    m = %{toe_share: n["toe_share"], sides: n["sides"], heels: n["heels"]}

    %{
      "animal_id" => animal.id,
      "event_type" => "hoof",
      "title" => Hooves.sole_title(p.foot, m),
      "description" => if(p.note != "", do: p.note),
      "event_date" => p.date,
      "photo_urls" => [url],
      "metadata" => Map.merge(n, %{"view" => "sole", "foot" => p.foot, "points" => p.points})
    }
  end

  defp event_attrs(animal, p, url) do
    %{
      "animal_id" => animal.id,
      "event_type" => "hoof",
      "title" => Hooves.title(p.foot, p.toe, p.pastern),
      "description" => if(p.note != "", do: p.note),
      "event_date" => p.date,
      "photo_urls" => [url],
      "metadata" => %{
        "foot" => p.foot,
        "toe" => p.toe,
        "pastern" => p.pastern,
        "points" => p.points
      }
    }
  end

  defp saved_message(%{view: "sole"} = p),
    do: "Saved #{Hooves.foot_name(p.foot)} sole: toe #{Hooves.fmt(p.nums["toe_share"])}%."

  defp saved_message(p),
    do: "Saved #{Hooves.foot_name(p.foot)}: toe #{Hooves.fmt(p.toe)}°."

  defp past_date(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, d} -> if Date.compare(d, Date.utc_today()) == :gt, do: Date.utc_today(), else: d
      _ -> Date.utc_today()
    end
  end

  defp reload(socket),
    do:
      socket
      |> assign(:animal, Animals.get_animal_with_pedigree!(socket.assigns.animal.id))
      |> load()

  defp load(socket) do
    events = socket.assigns.animal.timeline_events
    ms = Hooves.measurements(events)
    soles = Hooves.soles(events)
    latest = Hooves.latest(ms)

    history =
      Enum.sort_by(ms ++ soles, &{&1.date, &1.inserted_at}, fn a, b -> a >= b end)

    assign(socket,
      measurements: ms,
      soles: soles,
      latest: latest,
      latest_sole: Hooves.latest(soles),
      pairs: Hooves.pairs(latest),
      history: history
    )
  end

  defp number(n) when is_number(n), do: Float.round(n * 1.0, 1)

  defp number(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> Float.round(f, 1)
      :error -> nil
    end
  end

  defp number(_), do: nil

  # Width ÷ length keeps two decimals (0.83, not 0.8).
  defp ratio(n) when is_number(n) and n > 0 and n < 5, do: Float.round(n * 1.0, 2)
  defp ratio(_), do: nil
end
