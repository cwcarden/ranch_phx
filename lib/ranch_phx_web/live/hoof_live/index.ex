defmodule RanchPhxWeb.HoofLive.Index do
  @moduledoc """
  Hoof angles from a photo: pick a foot, take a level side photo, tap along the ground,
  the toe wall and (optionally) the pastern. The angles are worked out on the device;
  the marked-up photo and the numbers are saved as a "hoof" timeline event.
  """
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1]
  alias RanchPhx.Animals
  alias RanchPhx.Animals.Hooves
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
     |> assign(:pending, nil)
     |> assign(:error, nil)
     |> assign(:viewing, nil)
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

  def handle_event("upload_change", _params, socket), do: {:noreply, socket}

  # The measuring screen sends the numbers first, then the marked-up photo.
  def handle_event("hoof_measured", params, socket) do
    toe = number(params["toe"])
    pastern = number(params["pastern"])
    foot = params["foot"]

    date =
      case Date.from_iso8601(to_string(params["date"])) do
        {:ok, d} -> if Date.compare(d, Date.utc_today()) == :gt, do: Date.utc_today(), else: d
        _ -> Date.utc_today()
      end

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
          pastern: if((pastern && pastern > 0) and pastern < 90, do: pastern),
          date: date,
          note: params["note"] |> to_string() |> String.trim() |> String.slice(0, 500),
          points: params["points"]
        }

        {:reply, %{ok: true}, assign(socket, pending: pending, error: nil)}
    end
  end

  def handle_event("view", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, :viewing, Enum.find(socket.assigns.measurements, &(to_string(&1.id) == id)))}

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

      if pending do
        {:ok, _} =
          Animals.create_event(%{
            "animal_id" => animal.id,
            "event_type" => "hoof",
            "title" => Hooves.title(pending.foot, pending.toe, pending.pastern),
            "description" => if(pending.note != "", do: pending.note),
            "event_date" => pending.date,
            "photo_urls" => [url],
            "metadata" => %{
              "foot" => pending.foot,
              "toe" => pending.toe,
              "pastern" => pending.pastern,
              "points" => pending.points
            }
          })

        {:noreply,
         socket
         |> assign(:pending, nil)
         |> reload()
         |> push_event("hoof-saved", %{})
         |> put_flash(
           :info,
           "Saved #{Hooves.foot_name(pending.foot)}: toe #{Hooves.fmt(pending.toe)}°."
         )}
      else
        {:noreply, assign(socket, :error, "Couldn't save that one. Try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp reload(socket),
    do:
      socket
      |> assign(:animal, Animals.get_animal_with_pedigree!(socket.assigns.animal.id))
      |> load()

  defp load(socket) do
    ms = Hooves.measurements(socket.assigns.animal.timeline_events)
    latest = Hooves.latest(ms)
    assign(socket, measurements: ms, latest: latest, pairs: Hooves.pairs(latest))
  end

  defp number(n) when is_number(n), do: Float.round(n * 1.0, 1)

  defp number(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> Float.round(f, 1)
      :error -> nil
    end
  end

  defp number(_), do: nil
end
