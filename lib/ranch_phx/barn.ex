defmodule RanchPhx.Barn do
  @moduledoc """
  Barn mode: the app with no connection.

  While online, the iPad keeps a `snapshot/0` of everything worth reading at the barn
  (animals, records, care due, treatments, training, notes, hoof angles, photos and
  papers). Offline, what's added (records, notes, training sessions, doses given,
  photos) waits on the iPad and comes here through `apply/2` when it's back online.
  Each addition carries an id from the iPad, so a retried sync never adds it twice.
  """
  alias RanchPhx.{Animals, Repo, Training, VoiceNotes}
  alias RanchPhx.Barn.Op
  alias RanchPhx.Animals.{CareSchedule, Hooves, Record}

  @photos_per_animal 40

  # ── Reading ─────────────────────────────────────────────────────────────────

  def snapshot do
    today = RanchPhx.LocalTime.today()
    labels = Animals.record_type_label_map()
    cats = Record.categories()
    cat_label = Map.new(cats, &{&1.id, &1.label})

    animals =
      for a <- Animals.list_animals(status: "active") do
        a = Animals.get_animal_with_pedigree!(a.id)
        animal(a, today, labels, cat_label)
      end

    %{
      generated_at: DateTime.utc_now(),
      today: today,
      animals: animals,
      categories: Enum.map(cats, &%{id: &1.id, label: &1.label, color: &1.color}),
      record_types:
        Animals.list_record_types_by_category()
        |> Map.new(fn {cat, types} ->
          {cat, Enum.map(types, &%{slug: &1.slug, label: &1.label})}
        end),
      activities: Enum.map(Training.list_activities(), &%{id: &1.id, name: &1.name}),
      feet: Enum.map(Hooves.feet(), fn {c, n} -> %{code: c, name: n} end)
    }
  end

  defp animal(a, today, labels, cat_label) do
    records = Enum.sort_by(a.records, &{Date.to_gregorian_days(&1.date || today), &1.id}, :desc)
    book = if a.kind == "horse", do: Training.active_book_for_animal(a.id)
    hooves = Hooves.latest(Hooves.measurements(a.timeline_events))

    %{
      id: a.id,
      name: a.name,
      kind: a.kind,
      sex: a.sex,
      breed: a.breed,
      color: a.color,
      markings: a.markings,
      birth_date: a.birth_date,
      registration_number: a.registration_number,
      cover: a.cover_photo_url,
      notes: a.notes,
      photos:
        a.photos
        |> Enum.sort_by(
          &{Date.to_gregorian_days(&1.taken_at || NaiveDateTime.to_date(&1.inserted_at)), &1.id},
          :desc
        )
        |> Enum.take(@photos_per_animal)
        |> Enum.map(
          &%{
            url: &1.url,
            caption: &1.caption,
            date: &1.taken_at || NaiveDateTime.to_date(&1.inserted_at)
          }
        ),
      records:
        Enum.map(records, fn r ->
          %{
            id: r.id,
            date: r.date,
            category: r.category,
            category_label: cat_label[r.category] || r.category,
            type: r.record_type,
            type_label: labels[r.record_type] || r.record_type,
            title: r.title,
            description: r.description,
            notes: r.notes,
            person: r.person,
            location: r.location,
            cost: r.cost && Decimal.to_string(r.cost),
            next_due_date: r.next_due_date
          }
        end),
      care_due:
        Enum.map(CareSchedule.due(a.records, today), fn d ->
          %{title: d.record.title, due: d.record.next_due_date, days: d.days, covers: d.covers}
        end),
      courses:
        Enum.map(CareSchedule.active_courses(a.records, today), fn c ->
          %{
            record_id: c.record.id,
            title: c.record.title,
            dates: c.dates,
            done: MapSet.to_list(c.done),
            given: c.given,
            total: c.total
          }
        end),
      hooves:
        Map.new(hooves, fn {foot, m} ->
          {foot,
           %{
             toe: m.toe,
             pastern: m.pastern,
             axis: Hooves.axis_text(m.axis),
             date: m.date,
             photo: m.photo
           }}
        end),
      notes_log:
        a.timeline_events
        |> Enum.filter(&(&1.event_type in ~w(note training)))
        |> Enum.sort_by(
          &{Date.to_gregorian_days(&1.event_date || NaiveDateTime.to_date(&1.inserted_at)),
           &1.id},
          :desc
        )
        |> Enum.take(40)
        |> Enum.map(&%{date: &1.event_date, title: &1.title, text: &1.description}),
      training:
        book &&
          %{
            book_id: book.id,
            sessions:
              Enum.map(Training.list_sessions(book.id, 20), fn s ->
                %{
                  date: s.date,
                  minutes: s.minutes,
                  note: s.note,
                  activities: Enum.map(s.activities, &(&1.activity && &1.activity.name))
                }
              end)
          },
      documents:
        Enum.map(
          a.documents,
          &%{title: &1.title, type: &1.doc_type, date: &1.doc_date, url: &1.file_url}
        )
    }
  end

  @doc "Every photo and image the snapshot shows, to keep on the device."
  def media_urls(%{animals: animals}) do
    animals
    |> Enum.flat_map(fn a ->
      [a.cover | Enum.map(a.photos, & &1.url)] ++ Enum.map(Map.values(a.hooves), & &1.photo)
    end)
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "/uploads/")))
    |> Enum.uniq()
  end

  # ── Writing (what was added offline) ────────────────────────────────────────

  @doc """
  Applies one offline addition: `{:ok, result}`, `{:ok, :already}` if it came before,
  or `{:error, message}`.
  """
  def apply(%{"client_id" => cid, "kind" => kind} = op, user) when is_binary(cid) and cid != "" do
    case Repo.get_by(Op, client_id: cid) do
      %{} ->
        {:ok, :already}

      nil ->
        Repo.transaction(fn ->
          case do_apply(kind, op, user) do
            {:ok, result} ->
              Repo.insert!(%Op{client_id: cid, kind: kind, result: result})
              result

            {:error, msg} ->
              Repo.rollback(msg)
          end
        end)
    end
  end

  def apply(_, _), do: {:error, "Not something the barn can save."}

  defp do_apply("record", op, user) do
    with {:ok, a} <- animal_for(op) do
      attrs = %{
        "animal_id" => a.id,
        "category" => op["category"],
        "record_type" => blank(op["type"]) || first_type(op["category"]),
        "title" => op["title"],
        "date" => op["date"],
        "notes" => blank(op["notes"]),
        "person" => blank(op["person"]),
        "location" => blank(op["location"]),
        "cost" => blank(op["cost"]),
        "next_due_date" => blank(op["next_due_date"]),
        "created_by" => user && user.email
      }

      case Animals.create_record(attrs) do
        {:ok, r} -> {:ok, %{"record_id" => r.id}}
        {:error, cs} -> {:error, "Record: " <> errors(cs)}
      end
    end
  end

  defp do_apply("note", op, user) do
    text = op["text"] |> to_string() |> String.trim()

    animal =
      case animal_for(op) do
        {:ok, a} -> a
        _ -> nil
      end

    cond do
      text == "" ->
        {:error, "Empty note."}

      # Said or typed to sort out later: the same review list as the Siri notes.
      op["review"] == true ->
        text =
          if animal && not String.contains?(String.downcase(text), String.downcase(animal.name)),
            do: "#{animal.name}: #{text}",
            else: text

        case VoiceNotes.create_from_text(user, text) do
          {:ok, notes} -> {:ok, %{"voice_note_ids" => Enum.map(notes, & &1.id)}}
          {:error, _} -> {:error, "Empty note."}
        end

      animal ->
        case Animals.create_event(%{
               "animal_id" => animal.id,
               "event_type" => "note",
               "title" => text |> String.split("\n") |> hd() |> String.slice(0, 80),
               "description" => text,
               "event_date" => op["date"] || RanchPhx.LocalTime.today()
             }) do
          {:ok, e} -> {:ok, %{"event_id" => e.id}}
          {:error, cs} -> {:error, "Note: " <> errors(cs)}
        end

      true ->
        {:error, "Pick the animal for this note."}
    end
  end

  defp do_apply("training", op, _user) do
    with {:ok, a} <- animal_for(op),
         %{} = book <-
           Training.active_book_for_animal(a.id) || {:error, "#{a.name} has no training book."} do
      activities =
        for id <- List.wrap(op["activity_ids"]),
            do: %{"activity_id" => id, "result" => op["result"] || "good"}

      case Training.save_session(%{
             "book_id" => book.id,
             "client_id" => op["client_id"],
             "date" => op["date"],
             "minutes" => op["minutes"],
             "note" => blank(op["note"]),
             "source" => "typed",
             "activities" => activities
           }) do
        {:ok, s} -> {:ok, %{"session_id" => s.id}}
        {:error, %Ecto.Changeset{} = cs} -> {:error, "Training: " <> errors(cs)}
        {:error, other} -> {:error, "Training: #{inspect(other)}"}
      end
    end
  end

  defp do_apply("dose", op, _user) do
    with {n, ""} <- Integer.parse(to_string(op["record_id"])),
         %Record{} = r <- Repo.get(Record, n),
         {:ok, d} <- Date.from_iso8601(to_string(op["date"])) do
      done = r.course_done || []
      done = if d in done, do: done, else: Enum.sort([d | done], Date)

      case Animals.update_record(r, %{course_done: done}) do
        {:ok, _} -> {:ok, %{"record_id" => r.id}}
        {:error, cs} -> {:error, "Dose: " <> errors(cs)}
      end
    else
      _ -> {:error, "That treatment isn't there anymore."}
    end
  end

  defp do_apply(_, _, _), do: {:error, "Not something the barn can save."}

  @doc """
  A photo taken offline: a hoof photo to measure later (`foot` and `view`), or a photo
  for the animal's Photos.
  """
  def save_photo(op, tmp_path, user) do
    cid = op["client_id"]

    case cid && Repo.get_by(Op, client_id: cid) do
      %{} ->
        {:ok, :already}

      _ ->
        with {:ok, a} <- animal_for(op) do
          result =
            if op["foot"] in Enum.map(Hooves.feet(), &elem(&1, 0)) do
              url = store(tmp_path, ["animals", "#{a.id}", "hooves"])
              view = if op["view"] == "sole", do: "sole", else: "side"
              {:ok, e} = Hooves.create_pending(a, op["foot"], view, url, date(op["date"]))
              %{"event_id" => e.id}
            else
              url = store(tmp_path, ["animals", "#{a.id}", "photos"])

              {:ok, p} =
                Animals.create_photo(%{
                  animal_id: a.id,
                  url: url,
                  caption: blank(op["caption"]),
                  taken_at: date(op["date"])
                })

              if is_nil(a.cover_photo_url), do: Animals.set_cover_photo(a.id, p.id)
              %{"photo_id" => p.id}
            end

          if cid, do: Repo.insert!(%Op{client_id: cid, kind: "photo", result: result})
          _ = user
          {:ok, result}
        end
    end
  end

  defp store(tmp, parts) do
    dir = Path.join([Application.app_dir(:ranch_phx, "priv/static/uploads") | parts])
    File.mkdir_p!(dir)
    name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}.jpg"
    File.cp!(tmp, Path.join(dir, name))
    "/uploads/" <> Enum.join(parts, "/") <> "/" <> name
  end

  # A record needs a type; the category's first when none was picked.
  defp first_type(category) do
    case Animals.list_record_types_by_category()[category] do
      [t | _] -> t.slug
      _ -> nil
    end
  end

  defp animal_for(op) do
    with {n, ""} <- Integer.parse(to_string(op["animal_id"])),
         %{} = a <- Repo.get(RanchPhx.Animals.Animal, n) do
      {:ok, a}
    else
      _ -> {:error, "Pick the animal."}
    end
  end

  defp date(v) do
    case Date.from_iso8601(to_string(v)) do
      {:ok, d} -> d
      _ -> RanchPhx.LocalTime.today()
    end
  end

  defp blank(v) when v in [nil, ""], do: nil
  defp blank(v), do: v

  defp errors(cs) do
    cs.errors |> Enum.map_join(", ", fn {f, {m, _}} -> "#{f} #{m}" end)
  end
end
