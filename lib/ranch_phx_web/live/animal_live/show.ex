defmodule RanchPhxWeb.AnimalLive.Show do
  use RanchPhxWeb, :live_view
  alias RanchPhx.Animals
  alias RanchPhx.Animals.{Animal, TimelineEvent, Record, CareSchedule, CarePreset, RecordsAI, Insights}
  alias RanchPhx.VoiceNotes
  alias RanchPhx.Training.Coach
  import RanchPhxWeb.TrainingComponents, only: [coach_answer: 1]
  alias RanchPhx.Accounts.Scope
  require Decimal

  @uploads_dir Application.app_dir(:ranch_phx, "priv/static/uploads")

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    animal = Animals.get_animal_with_pedigree!(id)
    {:ok,
     socket
     |> assign(:animal, animal)
     |> assign(:side_rows, RanchPhxWeb.AnimalSidebar.rows())
     |> assign(:tab, "overview")
     |> assign(:edit_modal, false)
     |> assign(:event_modal, false)
     |> assign(:animal_changeset, Animals.change_animal(animal))
     |> assign(:event_changeset, TimelineEvent.changeset(%TimelineEvent{}, %{}))
     |> assign(:all_animals, Animals.list_all_animals_for_pedigree())
     |> assign(:record_modal, false)
     |> assign(:record_editing, nil)
     |> assign(:record_changeset, Animals.change_record(%Record{}))
     |> assign(:record_filter_cat, "")
     |> assign(:record_draft, nil)
     |> assign(:record_search, "")
     |> assign(:ai_on, Coach.configured?())
     |> assign(:summary, nil)
     |> assign(:summary_loading, false)
     |> assign(:rec_voice_open, false)
     |> assign(:rec_voice_text, "")
     |> assign(:rec_voice_loading, false)
     |> assign(:rec_voice_error, nil)
     |> assign(:voice_note, nil)
     |> assign(:doc_filter_type, "")
     |> assign(:presets, Animals.list_care_presets(animal.kind))
     |> assign(:quick_selected, [])
     |> assign(:visit, nil)
     |> assign(:editing_presets, false)
     |> assign(:scan_loading, false)
     |> assign(:measure, nil)
     |> assign(:data_metric, nil)
     |> assign(:data_pick, [])
     |> assign(:data_edit, false)
     |> assign(:scan_error, nil)
     |> assign(:preset_error, nil)
     |> assign(:tl_search, "")
     |> assign(:record_types_by_cat, Animals.list_record_types_by_category())
     |> assign(:type_label_map, Animals.record_type_label_map())
     |> assign(:categories, Record.categories())
     |> assign(:exp_year, Integer.to_string(Date.utc_today().year))
     |> assign(:exp_search, "")
     |> assign(:report_modal, false)
     |> assign(:doc_search, "")
     |> assign(:doc_form_title, "")
     |> assign(:doc_form_type, "")
     |> assign(:doc_form_date, "")
     |> assign(:doc_types, Animals.list_doc_types())
     |> assign(:new_doc_type, "")
     |> assign(:is_superuser, Scope.superuser?(socket.assigns[:current_scope]))
     |> assign(:show_more, false)
     |> assign(:show_type_manager, false)
     |> assign(:adding_category, false)
     |> assign(:new_category_label, "")
     |> assign(:new_category_color, "#6366f1")
     |> assign(:category_error, nil)
     |> assign(:adding_type_cat, nil)
     |> assign(:new_type_label, "")
     |> assign(:type_error, nil)
     |> assign(:pedigree_map, Animals.list_pedigree_entries(animal.id))
     |> assign(:ped_cols, pedigree_cols())
     |> assign(:ped_editing, nil)
     |> assign(:ped_form, %{})
     |> assign(:lightbox_url, nil)
     |> assign(:compare_pick, nil)
     |> assign(:compare_open, false)
     |> allow_upload(:photo, accept: ~w(.jpg .jpeg .png .webp .gif .heic .heif), max_entries: 10, max_file_size: 20_000_000)
     |> allow_upload(:document, accept: ~w(.pdf .doc .docx .jpg .jpeg .png .txt), max_entries: 5, max_file_size: 50_000_000)
     |> allow_upload(:scan, accept: ~w(.jpg .jpeg .png .webp .pdf), max_entries: 1, max_file_size: 25_000_000, auto_upload: true, progress: &handle_progress/3)
     |> allow_upload(:visit_doc, accept: ~w(.pdf .doc .docx .jpg .jpeg .png .heic .txt), max_entries: 5, max_file_size: 50_000_000)
     |> allow_upload(:record_doc, accept: ~w(.pdf .doc .docx .jpg .jpeg .png .txt), max_entries: 5, max_file_size: 50_000_000)}
  end

  @impl true
  # Links from the animal cards: ?data=weight (or ?weight=1) opens the growth data,
  # ?tab=records a tab.
  def handle_params(params, _uri, socket) do
    socket =
      case params["tab"] do
        tab when tab in ~w(overview records documents photos pedigree timeline genetics expenses) ->
          assign(socket, :tab, tab)

        _ ->
          socket
      end

    metric =
      cond do
        params["data"] in ~w(weight height) -> params["data"]
        params["weight"] -> "weight"
        true -> nil
      end

    socket = if(metric, do: open_data(socket, metric), else: socket)

    # From the Siri voice log: draft records from what was said, to check and save.
    socket =
      if params["voice"] && connected?(socket), do: open_voice_note(socket, params["voice"]), else: socket

    {:noreply, socket}
  end

  defp open_voice_note(socket, id) do
    %{animal: animal, is_superuser: su?, voice_note: current} = socket.assigns

    case su? && VoiceNotes.get(id) do
      %{status: "pending", animal_id: animal_id} = note when animal_id == animal.id ->
        if current && current.id == note.id do
          socket
        else
          socket
          |> assign(tab: "records", rec_voice_open: true, voice_note: note)
          |> start_voice_draft(note.text)
        end

      _ ->
        socket
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> assign(:tab, tab) |> assign(:show_more, false)}
  end

  def handle_event("toggle_more", _params, socket) do
    {:noreply, assign(socket, :show_more, !socket.assigns.show_more)}
  end

  def handle_event("close_more", _params, socket) do
    {:noreply, assign(socket, :show_more, false)}
  end

  def handle_event("open_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:edit_modal, true)
     |> assign(:animal_changeset, Animals.change_animal(socket.assigns.animal))}
  end

  def handle_event("close_edit", _params, socket) do
    {:noreply, assign(socket, :edit_modal, false)}
  end

  def handle_event("save_animal", %{"animal" => params}, socket) do
    case Animals.update_animal(socket.assigns.animal, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:animal, Animals.get_animal_with_pedigree!(updated.id))
         |> assign(:edit_modal, false)
         |> put_flash(:info, "Saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :animal_changeset, changeset)}
    end
  end

  def handle_event("open_event", _params, socket) do
    {:noreply,
     socket
     |> assign(:event_modal, true)
     |> assign(:event_changeset, TimelineEvent.changeset(%TimelineEvent{}, %{}))}
  end

  def handle_event("close_event", _params, socket) do
    {:noreply, assign(socket, :event_modal, false)}
  end

  def handle_event("save_event", %{"timeline_event" => params}, socket) do
    merged = Map.put(params, "animal_id", socket.assigns.animal.id)
    case Animals.create_event(merged) do
      {:ok, _} ->
        animal = Animals.get_animal_with_pedigree!(socket.assigns.animal.id)
        {:noreply,
         socket
         |> assign(:animal, animal)
         |> assign(:event_modal, false)
         |> put_flash(:info, "Event added.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :event_changeset, changeset)}
    end
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    event = Enum.find(socket.assigns.animal.timeline_events, &("#{&1.id}" == id))
    if event, do: Animals.delete_event(event)
    animal = Animals.get_animal_with_pedigree!(socket.assigns.animal.id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("upload_photos", _params, socket) do
    animal_id = socket.assigns.animal.id
    dir = Path.join([@uploads_dir, "animals", "#{animal_id}", "photos"])
    File.mkdir_p!(dir)

    uploaded = consume_uploaded_entries(socket, :photo, fn %{path: tmp}, entry ->
      orig_ext = entry.client_name |> Path.extname() |> String.downcase()
      heic? = orig_ext in [".heic", ".heif"]
      ext  = if heic?, do: ".jpg", else: orig_ext
      name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}#{ext}"
      dest = Path.join(dir, name)

      ok? = if heic? do
        heif = System.find_executable("heif-convert") || "/usr/bin/heif-convert"
        case System.cmd(heif, [tmp, dest], stderr_to_stdout: true) do
          {_, 0} -> true
          {out, code} ->
            require Logger
            Logger.error("heif-convert failed (#{code}): #{out}")
            false
        end
      else
        File.cp!(tmp, dest)
        true
      end

      if ok?, do: {:ok, "/uploads/animals/#{animal_id}/photos/#{name}"}, else: {:ok, nil}
    end)

    for url <- Enum.reject(uploaded, &is_nil/1) do
      Animals.create_photo(%{animal_id: animal_id, url: url})
    end

    if length(uploaded) > 0 && is_nil(socket.assigns.animal.cover_photo_url) do
      first_photo = Animals.list_photos(animal_id) |> List.first()
      if first_photo, do: Animals.set_cover_photo(animal_id, first_photo.id)
    end

    animal = Animals.get_animal_with_pedigree!(animal_id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("set_cover", %{"id" => photo_id}, socket) do
    Animals.set_cover_photo(socket.assigns.animal.id, String.to_integer(photo_id))
    animal = Animals.get_animal_with_pedigree!(socket.assigns.animal.id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("set_cover_position", %{"pos" => pos}, socket) when pos in ~w(top center bottom) do
    Animals.update_animal(socket.assigns.animal, %{cover_position: pos})
    animal = Animals.get_animal_with_pedigree!(socket.assigns.animal.id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("delete_photo", %{"id" => photo_id}, socket) do
    photo = Enum.find(socket.assigns.animal.photos, &("#{&1.id}" == photo_id))
    if photo do
      Animals.delete_photo(photo)
      if socket.assigns.animal.cover_photo_url == photo.url do
        Animals.update_animal(socket.assigns.animal, %{cover_photo_url: nil})
      end
    end
    animal = Animals.get_animal_with_pedigree!(socket.assigns.animal.id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("upload_document", %{"doc" => params}, socket) do
    animal_id = socket.assigns.animal.id
    dir = Path.join([@uploads_dir, "animals", "#{animal_id}", "documents"])
    File.mkdir_p!(dir)

    uploaded = consume_uploaded_entries(socket, :document, fn %{path: tmp}, entry ->
      ext  = Path.extname(entry.client_name)
      name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}#{ext}"
      dest = Path.join(dir, name)
      File.cp!(tmp, dest)
      url = "/uploads/animals/#{animal_id}/documents/#{name}"
      {:ok, {url, entry}}
    end)

    for {url, entry} <- uploaded do
      title = params |> Map.get("title", "") |> String.trim()
      title = if title == "", do: entry.client_name, else: title
      doc_type = params |> Map.get("doc_type", "") |> String.trim()
      doc_type = if doc_type == "", do: nil, else: doc_type

      doc_date = params |> Map.get("doc_date", "") |> String.trim()

      Animals.create_document(%{
        animal_id: animal_id,
        title: title,
        doc_type: doc_type,
        doc_date: if(doc_date != "", do: doc_date, else: nil),
        file_url: url,
        mime_type: entry.client_type,
        file_size: entry.client_size
      })
    end

    animal = Animals.get_animal_with_pedigree!(animal_id)
    {:noreply,
     socket
     |> assign(:animal, animal)
     |> assign(:doc_form_title, "")
     |> assign(:doc_form_type, "")
     |> assign(:doc_form_date, "")
     |> put_flash(:info, "Document uploaded.")}
  end

  def handle_event("delete_document", %{"id" => doc_id}, socket) do
    doc = Enum.find(socket.assigns.animal.documents, &("#{&1.id}" == doc_id))
    if doc, do: Animals.delete_document(doc)
    animal = Animals.get_animal_with_pedigree!(socket.assigns.animal.id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("toggle_favorite", _params, socket) do
    a = socket.assigns.animal
    Animals.update_animal(a, %{is_favorite: !a.is_favorite})
    animal = Animals.get_animal_with_pedigree!(a.id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("tl_search", %{"value" => val}, socket) do
    {:noreply, assign(socket, :tl_search, val)}
  end

  def handle_event("doc_search", %{"value" => val}, socket) do
    {:noreply, assign(socket, :doc_search, val)}
  end

  def handle_event("add_doc_type", %{"name" => name}, socket) do
    name = String.trim(name)
    if name != "" do
      Animals.create_doc_type(%{"name" => name})
    end
    {:noreply, assign(socket, doc_types: Animals.list_doc_types(), new_doc_type: "")}
  end

  def handle_event("delete_doc_type", %{"id" => id}, socket) do
    dt = Enum.find(socket.assigns.doc_types, &("#{&1.id}" == id))
    if dt, do: Animals.delete_doc_type(dt)
    {:noreply, assign(socket, :doc_types, Animals.list_doc_types())}
  end

  def handle_event("filter_records", %{"cat" => cat}, socket) do
    {:noreply, assign(socket, :record_filter_cat, cat)}
  end

  def handle_event("toggle_type_manager", _params, socket) do
    {:noreply, assign(socket, :show_type_manager, !socket.assigns.show_type_manager)}
  end

  def handle_event("start_add_category", _params, socket) do
    {:noreply, assign(socket, adding_category: true, new_category_label: "", new_category_color: "#6366f1", category_error: nil)}
  end

  def handle_event("cancel_add_category", _params, socket) do
    {:noreply, assign(socket, adding_category: false, category_error: nil)}
  end

  def handle_event("update_category_label", %{"value" => label}, socket) do
    {:noreply, assign(socket, new_category_label: label, category_error: nil)}
  end

  def handle_event("pick_category_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, :new_category_color, color)}
  end

  def handle_event("save_category", _params, socket) do
    label = String.trim(socket.assigns.new_category_label)

    if label == "" do
      {:noreply, assign(socket, :category_error, "Label cannot be blank.")}
    else
      slug = label |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")

      case Animals.create_category(%{slug: slug, label: label, color: socket.assigns.new_category_color, position: 999}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(adding_category: false, new_category_label: "", category_error: nil)
           |> assign(:categories, Record.categories())}

        {:error, cs} ->
          msg = cs.errors |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end) |> Enum.join(", ")
          {:noreply, assign(socket, :category_error, msg)}
      end
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    Animals.get_category!(String.to_integer(id)) |> Animals.delete_category()
    {:noreply, assign(socket, :categories, Record.categories())}
  end

  def handle_event("start_add_type", %{"cat" => cat}, socket) do
    {:noreply, assign(socket, adding_type_cat: cat, new_type_label: "", type_error: nil)}
  end

  def handle_event("cancel_add_type", _params, socket) do
    {:noreply, assign(socket, adding_type_cat: nil, type_error: nil)}
  end

  def handle_event("update_type_label", %{"value" => label}, socket) do
    {:noreply, assign(socket, new_type_label: label, type_error: nil)}
  end

  def handle_event("save_type", %{"cat" => cat}, socket) do
    label = String.trim(socket.assigns.new_type_label)

    if label == "" do
      {:noreply, assign(socket, :type_error, "Label cannot be blank.")}
    else
      slug = label |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")

      case Animals.create_record_type(%{category: cat, slug: slug, label: label, position: 999}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(adding_type_cat: nil, new_type_label: "", type_error: nil)
           |> assign(:record_types_by_cat, Animals.list_record_types_by_category())
           |> assign(:type_label_map, Animals.record_type_label_map())}

        {:error, cs} ->
          msg = cs.errors |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end) |> Enum.join(", ")
          {:noreply, assign(socket, :type_error, msg)}
      end
    end
  end

  def handle_event("delete_record_type", %{"id" => id}, socket) do
    Animals.get_record_type!(String.to_integer(id)) |> Animals.delete_record_type()
    {:noreply,
     socket
     |> assign(:record_types_by_cat, Animals.list_record_types_by_category())
     |> assign(:type_label_map, Animals.record_type_label_map())}
  end

  def handle_event("open_record", _params, socket) do
    {:noreply,
     socket
     |> assign(:record_modal, true)
     |> assign(:record_editing, nil)
     |> assign(:record_draft, nil)
     |> assign(:record_changeset, Animals.change_record(%Record{}))}
  end

  def handle_event("edit_record", %{"id" => id}, socket) do
    record = Enum.find(socket.assigns.animal.records, &("#{&1.id}" == id))
    {:noreply,
     socket
     |> assign(:record_modal, true)
     |> assign(:record_editing, record)
     |> assign(:record_changeset, Animals.change_record(record))}
  end

  # ── Quick add: pick one or more, then fill in one visit ──

  def handle_event("toggle_quick", %{"id" => id}, socket) do
    id = String.to_integer(id)
    sel = socket.assigns.quick_selected
    sel = if id in sel, do: List.delete(sel, id), else: sel ++ [id]
    {:noreply, assign(socket, :quick_selected, sel)}
  end

  def handle_event("clear_quick", _params, socket),
    do: {:noreply, assign(socket, :quick_selected, [])}

  def handle_event("start_visit", _params, socket) do
    %{presets: presets, quick_selected: sel} = socket.assigns
    picked = for id <- sel, p = Enum.find(presets, &(&1.id == id)), do: p
    today = Date.utc_today()

    visit = %{
      "date" => Date.to_iso8601(today),
      "person" => last_person(socket.assigns.animal.records),
      "location" => "",
      "notes" => "",
      "items" => Enum.map(picked, &visit_item(&1, today))
    }

    {:noreply, assign(socket, visit: visit, quick_selected: [])}
  end

  def handle_event("close_visit", _params, socket), do: {:noreply, assign(socket, :visit, nil)}

  def handle_event("visit_change", %{"visit" => params} = payload, socket) do
    {:noreply,
     assign(socket, :visit, merge_visit(socket.assigns.visit, params, payload["_target"]))}
  end

  def handle_event("pick_product", %{"i" => i, "product" => product}, socket) do
    {:noreply, update_item(socket, String.to_integer(i), &Map.put(&1, "product", product))}
  end

  def handle_event("remove_visit_item", %{"i" => i}, socket) do
    items = List.delete_at(socket.assigns.visit["items"], String.to_integer(i))
    visit = if items == [], do: nil, else: Map.put(socket.assigns.visit, "items", items)
    {:noreply, assign(socket, :visit, visit)}
  end

  def handle_event("save_visit", %{"visit" => params}, socket) do
    %{animal: animal, is_superuser: su?} = socket.assigns
    visit = merge_visit(socket.assigns.visit, params, nil)

    if su? and visit do
      results =
        for item <- visit["items"] do
          Animals.create_record(%{
            "animal_id" => animal.id,
            "record_type" => item["record_type"],
            "title" => item["title"],
            "description" => describe(item, visit["date"]),
            "date" => blank(item["date"]) || visit["date"],
            "next_due_date" => blank(item["next_due"]),
            "cost" => blank(item["cost"]),
            "person" => blank(visit["person"]),
            "location" => blank(visit["location"]),
            "notes" => blank(visit["notes"])
          })
        end

      case Enum.filter(results, &match?({:error, _}, &1)) do
        [] ->
          save_visit_docs(socket, animal, visit)
          attach_scan(animal, visit)
          n = length(results)
          voice = socket.assigns.voice_note
          if voice, do: VoiceNotes.mark(voice, "done")

          {:noreply,
           socket
           |> assign(:animal, Animals.get_animal_with_pedigree!(animal.id))
           |> assign(:visit, nil)
           |> assign(:voice_note, nil)
           |> put_flash(
             :info,
             "Added #{n} #{if n == 1, do: "record", else: "records"}#{if voice, do: " from your voice note"}."
           )}

        [{:error, cs} | _] ->
          msg =
            cs.errors
            |> Enum.map_join(", ", fn {f, {m, _}} -> "#{Phoenix.Naming.humanize(f)} #{m}" end)

          {:noreply, assign(socket, :visit, Map.put(visit, "error", "Couldn't save: #{msg}"))}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Editing the quick-add buttons ──

  def handle_event("toggle_presets", _params, socket),
    do:
      {:noreply,
       assign(socket, editing_presets: !socket.assigns.editing_presets, preset_error: nil)}

  def handle_event("preset_save", %{"preset" => params}, socket) do
    %{animal: animal, is_superuser: su?} = socket.assigns

    result =
      cond do
        not su? -> :skip
        params["id"] in [nil, ""] -> Animals.create_care_preset(animal.kind, params)
        true -> params["id"] |> Animals.get_care_preset!() |> Animals.update_care_preset(params)
      end

    case result do
      {:error, cs} ->
        msg =
          Enum.map_join(cs.errors, ", ", fn {f, {m, _}} ->
            "#{Phoenix.Naming.humanize(f)} #{m}"
          end)

        {:noreply, assign(socket, :preset_error, msg)}

      _ ->
        {:noreply,
         assign(socket, presets: Animals.list_care_presets(animal.kind), preset_error: nil)}
    end
  end

  def handle_event("preset_delete", %{"id" => id}, socket) do
    if socket.assigns.is_superuser,
      do: id |> Animals.get_care_preset!() |> Animals.delete_care_preset()

    {:noreply,
     assign(socket,
       presets: Animals.list_care_presets(socket.assigns.animal.kind),
       quick_selected: List.delete(socket.assigns.quick_selected, String.to_integer(id))
     )}
  end

  # "+ Log" on a due item: the same kind of record again, dated today, with the
  # same gap to the next one as last time.
  def handle_event("redo_record", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.animal.records, &("#{&1.id}" == id)) do
      nil ->
        {:noreply, socket}

      r ->
        today = Date.utc_today()
        gap = r.next_due_date && Date.diff(r.next_due_date, r.date)

        draft = %Record{
          record_type: r.record_type,
          title: r.title,
          date: today,
          next_due_date: gap && gap > 0 && Date.add(today, gap),
          person: r.person,
          location: r.location
        }

        {:noreply,
         socket
         |> assign(:record_modal, true)
         |> assign(:record_editing, nil)
         |> assign(:record_draft, draft)
         |> assign(:record_changeset, Animals.change_record(%Record{}))}
    end
  end

  # ── Weigh-in ──

  # Log a weight or a height: a number, how it was measured, the date and a note.
  def handle_event("open_measure", %{"metric" => metric}, socket) when metric in ~w(weight height) do
    method =
      Insights.latest_method(socket.assigns.animal.timeline_events, metric) ||
        if(metric == "weight", do: "scale", else: "stick")

    {:noreply,
     assign(socket, :measure, %{
       "metric" => metric,
       "date" => Date.to_iso8601(Date.utc_today()),
       "value" => "",
       "method" => method,
       "note" => "",
       "error" => nil
     })}
  end

  def handle_event("close_measure", _params, socket), do: {:noreply, assign(socket, :measure, nil)}

  def handle_event("measure_change", %{"measure" => params}, socket),
    do: {:noreply, assign(socket, :measure, Map.merge(socket.assigns.measure, params))}

  def handle_event("save_measure", %{"measure" => params}, socket) do
    %{animal: animal, is_superuser: su?} = socket.assigns
    m = Map.merge(socket.assigns.measure, params)
    weight? = m["metric"] == "weight"
    methods = if weight?, do: ~w(scale tape estimate), else: ~w(stick tape estimate)
    method = if m["method"] in methods, do: m["method"]

    # Weight in pounds; height typed in hands (14.2) or inches (58 in).
    value =
      if weight? do
        case Float.parse(String.replace("#{m["value"]}", ",", "")) do
          {n, _} when n >= 1 and n <= 5000 -> round(n)
          _ -> nil
        end
      else
        Insights.parse_height(m["value"])
      end

    cond do
      not su? ->
        {:noreply, socket}

      is_nil(value) ->
        msg = if weight?, do: "Enter the weight in pounds.", else: "Enter the height in hands, like 14.2."
        {:noreply, assign(socket, :measure, Map.put(m, "error", msg))}

      true ->
        {title, meta} =
          if weight?,
            do: {"#{value} lb", %{"lbs" => value}},
            else: {"#{Insights.hands(value)} hh", %{"inches" => value}}

        attrs = %{
          "animal_id" => animal.id,
          "event_type" => m["metric"],
          "title" => "#{title}#{if method, do: " (#{method})"}",
          "description" => blank(m["note"]),
          "event_date" => m["date"],
          "metadata" => Map.put(meta, "method", method)
        }

        result =
          case m["event_id"] && Enum.find(animal.timeline_events, &(to_string(&1.id) == to_string(m["event_id"]))) do
            %{} = event -> Animals.update_event(event, attrs)
            _ -> Animals.create_event(attrs)
          end

        case result do
          {:ok, _} ->
            socket = assign(socket, :animal, Animals.get_animal_with_pedigree!(animal.id))

            {:noreply,
             socket
             |> assign(:measure, nil)
             |> then(&if(&1.assigns.data_metric, do: open_data(&1, &1.assigns.data_metric), else: &1))
             |> put_flash(:info, "#{if m["event_id"], do: "Updated", else: "Saved"}: #{title}.")}

          {:error, cs} ->
            msg = Enum.map_join(cs.errors, ", ", fn {f, {e, _}} -> "#{Phoenix.Naming.humanize(f)} #{e}" end)
            {:noreply, assign(socket, :measure, Map.put(m, "error", msg))}
        end
    end
  end

  # ── Growth data (weight and height history) ──

  def handle_event("open_data", %{"metric" => metric}, socket) when metric in ~w(weight height),
    do: {:noreply, open_data(socket, metric)}

  # Tick off (or untick) one day of a multi-day treatment.
  def handle_event("course_toggle", %{"id" => id, "date" => date}, socket) do
    %{animal: animal, is_superuser: su?} = socket.assigns

    with true <- su?,
         %{} = r <- Enum.find(animal.records, &(to_string(&1.id) == id)),
         {:ok, d} <- Date.from_iso8601(date),
         false <- Date.compare(d, Date.utc_today()) == :gt do
      done = r.course_done || []
      done = if d in done, do: List.delete(done, d), else: Enum.sort([d | done], Date)
      {:ok, _} = Animals.update_record(r, %{course_done: done})
      {:noreply, assign(socket, :animal, Animals.get_animal_with_pedigree!(animal.id))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_data", _params, socket),
    do: {:noreply, assign(socket, data_metric: nil, data_pick: [], data_edit: false)}

  def handle_event("toggle_data_edit", _params, socket),
    do: {:noreply, assign(socket, :data_edit, !socket.assigns.data_edit)}

  # Fix a past weight or height: opens the log form filled in with that day's entry.
  def handle_event("edit_entry", %{"date" => date}, socket) do
    metric = socket.assigns.data_metric

    case socket.assigns.is_superuser && entry_event(socket.assigns.animal, metric, date) do
      %{} = e ->
        meta = e.metadata || %{}

        value =
          if metric == "weight",
            do: to_string(meta["lbs"] || Insights.parse_weight(e.title) || ""),
            else: (fn i -> if i, do: Insights.hands(i), else: "" end).(meta["inches"] || Insights.parse_height(e.title))

        {:noreply,
         assign(socket, :measure, %{
           "metric" => metric,
           "event_id" => e.id,
           "value" => value,
           "method" => meta["method"],
           "date" => Date.to_iso8601(e.event_date),
           "note" => e.description || "",
           "error" => nil
         })}

      _ ->
        {:noreply, put_flash(socket, :error, "That one came from a record. Change it on the Records tab.")}
    end
  end

  def handle_event("delete_entry", _params, socket) do
    %{animal: animal, measure: m, is_superuser: su?} = socket.assigns

    with true <- su?,
         %{} = e <- Enum.find(animal.timeline_events, &(to_string(&1.id) == to_string(m["event_id"]))),
         {:ok, _} <- Animals.delete_event(e) do
      socket = assign(socket, animal: Animals.get_animal_with_pedigree!(animal.id), measure: nil)

      {:noreply,
       socket
       |> then(&if(&1.assigns.data_metric, do: open_data(&1, &1.assigns.data_metric), else: &1))
       |> put_flash(:info, "Deleted that #{m["metric"]}.")}
    else
      _ -> {:noreply, socket}
    end
  end

  # Tap two entries to compare them; a third tap starts a new pair.
  def handle_event("pick_point", %{"i" => i}, socket) do
    i = String.to_integer(i)

    pick =
      case socket.assigns.data_pick do
        [^i] -> []
        [a] -> [a, i]
        _ -> [i]
      end

    {:noreply, assign(socket, :data_pick, pick)}
  end

  def handle_event("record_search", %{"value" => q}, socket),
    do: {:noreply, assign(socket, :record_search, q)}

  def handle_event("filter_docs", %{"type" => type}, socket),
    do: {:noreply, assign(socket, :doc_filter_type, type)}

  # ── AI on records ──

  def handle_event("summarize_records", _params, socket) do
    %{animal: animal} = socket.assigns

    {:noreply,
     socket
     |> assign(:summary_loading, true)
     |> start_async(:rec_summary, fn ->
       RecordsAI.summarize(animal, animal.records, animal.documents, Date.utc_today())
     end)}
  end

  def handle_event("close_summary", _params, socket),
    do: {:noreply, assign(socket, :summary, nil)}

  def handle_event("toggle_rec_voice", _params, socket),
    do: {:noreply, assign(socket, :rec_voice_open, !socket.assigns.rec_voice_open)}

  def handle_event("rec_voice_typing", %{"spoken" => text}, socket),
    do: {:noreply, assign(socket, :rec_voice_text, text)}

  def handle_event("rec_voice_draft", %{"spoken" => text}, socket) do
    %{is_superuser: su?, rec_voice_loading: busy?} = socket.assigns

    if su? and not busy? and String.trim(text) != "" do
      {:noreply, start_voice_draft(socket, text)}
    else
      {:noreply, assign(socket, :rec_voice_text, text)}
    end
  end

  def handle_event("scan_validate", _params, socket),
    do: {:noreply, assign(socket, :scan_error, nil)}

  def handle_event("close_record", _params, socket) do
    {:noreply, assign(socket, :record_modal, false)}
  end

  def handle_event("save_record", %{"record" => params}, socket) do
    animal_id = socket.assigns.animal.id

    # handle tags: split comma-separated string into list
    params = case Map.get(params, "tags") do
      nil -> params
      "" -> Map.put(params, "tags", [])
      tags_str -> Map.put(params, "tags", tags_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")))
    end

    result = case socket.assigns.record_editing do
      nil -> Animals.create_record(Map.put(params, "animal_id", animal_id))
      rec -> Animals.update_record(rec, params)
    end

    case result do
      {:ok, _} ->
        doc_dir = Path.join([@uploads_dir, "animals", "#{animal_id}", "documents"])
        File.mkdir_p!(doc_dir)
        record_title = params |> Map.get("title", "") |> String.trim()
        record_type  = params |> Map.get("record_type", "")
        record_date  = params |> Map.get("date", "")
        doc_type     = if record_type != "", do: Record.type_label(record_type), else: nil
        n_files      = length(socket.assigns.uploads.record_doc.entries)
        consume_uploaded_entries(socket, :record_doc, fn %{path: tmp}, entry ->
          ext  = Path.extname(entry.client_name)
          name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}#{ext}"
          dest = Path.join(doc_dir, name)
          File.cp!(tmp, dest)
          url = "/uploads/animals/#{animal_id}/documents/#{name}"
          title = cond do
            record_title == ""  -> entry.client_name
            n_files == 1        -> record_title
            true                -> "#{record_title} — #{Path.basename(entry.client_name, ext)}"
          end
          Animals.create_document(%{
            animal_id: animal_id,
            title: title,
            doc_type: doc_type,
            doc_date: if(record_date != "", do: record_date, else: nil),
            file_url: url,
            mime_type: entry.client_type,
            file_size: entry.client_size
          })
          {:ok, url}
        end)
        animal = Animals.get_animal_with_pedigree!(animal_id)
        {:noreply,
         socket
         |> assign(:animal, animal)
         |> assign(:record_modal, false)
         |> put_flash(:info, "Record saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :record_changeset, changeset)}
    end
  end

  def handle_event("delete_record", %{"id" => id}, socket) do
    record = Enum.find(socket.assigns.animal.records, &("#{&1.id}" == id))
    if record, do: Animals.delete_record(record)
    animal = Animals.get_animal_with_pedigree!(socket.assigns.animal.id)
    {:noreply, assign(socket, :animal, animal)}
  end

  def handle_event("exp_year", %{"year" => year}, socket) do
    {:noreply, assign(socket, :exp_year, year)}
  end

  def handle_event("exp_search", %{"value" => val}, socket) do
    {:noreply, assign(socket, :exp_search, val)}
  end

  def handle_event("open_report", _params, socket) do
    {:noreply, assign(socket, :report_modal, true)}
  end

  def handle_event("close_report", _params, socket) do
    {:noreply, assign(socket, :report_modal, false)}
  end

  # Compare two photos: "Compare" turns on picking, two taps open the comparison.
  def handle_event("compare_start", _params, socket),
    do: {:noreply, assign(socket, compare_pick: [], compare_open: false)}

  def handle_event("compare_cancel", _params, socket),
    do: {:noreply, assign(socket, compare_pick: nil, compare_open: false)}

  def handle_event("compare_pick", %{"id" => id}, socket) do
    id = String.to_integer(id)
    pick = socket.assigns.compare_pick || []
    pick = if id in pick, do: List.delete(pick, id), else: pick ++ [id]
    {:noreply, assign(socket, compare_pick: pick, compare_open: length(pick) == 2)}
  end

  def handle_event("compare_close", _params, socket),
    do: {:noreply, assign(socket, compare_pick: [], compare_open: false)}

  def handle_event("open_lightbox", %{"url" => url}, socket) do
    {:noreply, assign(socket, :lightbox_url, url)}
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_url, nil)}
  end

  def handle_event("validate_photo",      _params, socket), do: {:noreply, socket}
  def handle_event("validate_record_doc", _params, socket), do: {:noreply, socket}

  def handle_event("validate_doc", %{"doc" => params}, socket) do
    {:noreply,
     socket
     |> assign(:doc_form_title, Map.get(params, "title", ""))
     |> assign(:doc_form_type, Map.get(params, "doc_type", ""))
     |> assign(:doc_form_date, Map.get(params, "doc_date", ""))}
  end
  def handle_event("validate_doc", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("delete_animal", _params, socket) do
    Animals.delete_animal(socket.assigns.animal)
    {:noreply, push_navigate(socket, to: "/")}
  end

  def error_to_string(:too_large),      do: "File too large"
  def error_to_string(:not_accepted),   do: "File type not accepted"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(_),               do: "Upload error"

  # ── Pedigree events ────────────────────────────────────────────────────────

  def handle_event("ped_edit", %{"slot" => slot}, socket) do
    existing = socket.assigns.pedigree_map[slot]
    form = if existing do
      %{"name" => existing.name || "",
        "registration_number" => existing.registration_number || "",
        "breed" => existing.breed || "",
        "birth_year" => (existing.birth_year && Integer.to_string(existing.birth_year)) || "",
        "color" => existing.color || "",
        "sex" => existing.sex || "",
        "notes" => existing.notes || ""}
    else
      %{"name" => "", "registration_number" => "", "breed" => "",
        "birth_year" => "", "color" => "", "sex" => "", "notes" => ""}
    end
    {:noreply, assign(socket, ped_editing: slot, ped_form: form)}
  end

  def handle_event("ped_cancel", _params, socket) do
    {:noreply, assign(socket, ped_editing: nil, ped_form: %{})}
  end

  def handle_event("ped_change", %{"entry" => params}, socket) do
    {:noreply, assign(socket, :ped_form, params)}
  end

  def handle_event("ped_save", %{"entry" => params}, socket) do
    slot = socket.assigns.ped_editing
    attrs = %{
      animal_id:           socket.assigns.animal.id,
      slot:                slot,
      name:                String.trim(params["name"] || ""),
      registration_number: String.trim(params["registration_number"] || ""),
      breed:               String.trim(params["breed"] || ""),
      birth_year:          parse_int(params["birth_year"]),
      color:               String.trim(params["color"] || ""),
      sex:                 String.trim(params["sex"] || ""),
      notes:               String.trim(params["notes"] || "")
    }

    case Animals.upsert_pedigree_entry(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(ped_editing: nil, ped_form: %{})
         |> assign(:pedigree_map, Animals.list_pedigree_entries(socket.assigns.animal.id))}
      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("ped_delete", %{"slot" => slot}, socket) do
    case socket.assigns.pedigree_map[slot] do
      nil -> {:noreply, socket}
      entry ->
        Animals.delete_pedigree_entry(entry)
        {:noreply,
         socket
         |> assign(ped_editing: nil, ped_form: %{})
         |> assign(:pedigree_map, Animals.list_pedigree_entries(socket.assigns.animal.id))}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def format_cost(nil), do: "—"
  def format_cost(%Decimal{} = d) do
    rounded = Decimal.round(d, 2) |> Decimal.to_string()
    [whole | rest] = String.split(rounded, ".")
    cents = case rest do
      [] -> "00"
      [c] -> String.pad_trailing(c, 2, "0")
    end
    negative = String.starts_with?(whole, "-")
    abs_whole = if negative, do: String.slice(whole, 1..-1//1), else: whole
    formatted = abs_whole |> String.graphemes() |> Enum.reverse()
      |> Enum.chunk_every(3) |> Enum.map(&Enum.reverse/1) |> Enum.reverse()
      |> Enum.map_join(",", &Enum.join/1)
    "#{if negative, do: "-", else: ""}$#{formatted}.#{cents}"
  end

  def result_chip_class(r) when is_binary(r) do
    cond do
      String.upcase(r) in ["N/N", "N", "CLEAR", "NEGATIVE"] -> "result-n"
      String.upcase(r) in ["N/H", "CARRIER", "HET", "C"]    -> "result-c"
      String.upcase(r) in ["H/H", "AFFECTED", "H"]          -> "result-h"
      String.upcase(r) in ["P", "POSITIVE", "POS"]          -> "result-p"
      true -> "result-u"
    end
  end
  def result_chip_class(_), do: "result-u"

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      :error  -> nil
    end
  end

  # Pedigree table rows for the chart.
  # @max_gen controls depth: 5 = 32 rows, 6 = 64 rows.
  # Change to 6 for six-generation chart (64-row table)
  @max_ped_gen 5

  def pedigree_cols do
    Enum.map(1..@max_ped_gen, fn gen ->
      slots = Enum.map(0..(Integer.pow(2, gen) - 1), &ped_slot_key(gen, &1))
      %{gen: gen, label: ped_gen_label(gen), slots: slots}
    end)
  end

  defp ped_slot_key(gen, idx) do
    Enum.map((gen - 1)..0//-1, fn bit ->
      if rem(div(idx, Integer.pow(2, bit)), 2) == 1, do: "D", else: "S"
    end)
    |> Enum.join()
  end

  def ped_slot_label(slot) do
    slot |> String.graphemes() |> Enum.map_join("'s ", fn "S" -> "Sire"; "D" -> "Dam" end)
  end

  def ped_gen_label(1), do: "Sire / Dam"
  def ped_gen_label(2), do: "Grandparents"
  def ped_gen_label(3), do: "Great-Grandparents"
  def ped_gen_label(4), do: "2× Great-Grandparents"
  def ped_gen_label(5), do: "3× Great-Grandparents"
  def ped_gen_label(6), do: "4× Great-Grandparents"
  def ped_gen_label(n), do: "Generation #{n}"

  # Open the horse's training book, or the start-a-book form with him picked.
  def training_href(animal) do
    case RanchPhx.Training.active_book_for_animal(animal.id) do
      nil -> ~p"/training?horse=#{animal.id}"
      book -> ~p"/training/#{book.id}"
    end
  end

  @impl true
  def handle_async(:rec_summary, {:ok, {:ok, text}}, socket),
    do: {:noreply, assign(socket, summary: {:ok, text}, summary_loading: false)}

  def handle_async(:rec_summary, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       assign(socket, summary: {:error, Coach.error_message(reason)}, summary_loading: false)}

  def handle_async(:rec_summary, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket,
         summary: {:error, "Something went wrong. Try again."},
         summary_loading: false
       )}

  def handle_async(:rec_draft, {:ok, {:ok, []}}, socket),
    do:
      {:noreply,
       assign(socket,
         rec_voice_loading: false,
         rec_voice_error: "Couldn't pick out any records. Try naming what was done."
       )}

  def handle_async(:rec_draft, {:ok, {:ok, drafts}}, socket),
    do:
      {:noreply,
       assign(socket,
         rec_voice_loading: false,
         rec_voice_text: "",
         visit: visit_from_drafts(drafts, socket.assigns.presets, nil)
       )}

  def handle_async(:scan, {:ok, {{:ok, []}, _attach}}, socket),
    do:
      {:noreply,
       assign(socket,
         scan_loading: false,
         scan_error:
           "Couldn't find any records on that. Try a clearer photo of the itemized part."
       )}

  def handle_async(:scan, {:ok, {{:ok, drafts}, attach}}, socket),
    do:
      {:noreply,
       assign(socket,
         scan_loading: false,
         visit: visit_from_drafts(drafts, socket.assigns.presets, attach)
       )}

  def handle_async(:scan, {:ok, {{:error, reason}, _}}, socket),
    do: {:noreply, assign(socket, scan_loading: false, scan_error: Coach.error_message(reason))}

  def handle_async(:scan, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket,
         scan_loading: false,
         scan_error: "Something went wrong reading that. Try again."
       )}

  def handle_async(:rec_draft, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       assign(socket, rec_voice_loading: false, rec_voice_error: Coach.error_message(reason))}

  def handle_async(:rec_draft, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket,
         rec_voice_loading: false,
         rec_voice_error: "Something went wrong. Try again."
       )}

  # A scanned photo or PDF arrives: keep a copy for the animal's documents, then
  # have the AI read it in the background.
  def handle_progress(:scan, entry, socket) do
    if entry.done? do
      %{animal: animal, presets: presets} = socket.assigns

      file =
        consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
          doc_dir = Path.join([@uploads_dir, "animals", "#{animal.id}", "documents"])
          File.mkdir_p!(doc_dir)
          ext = Path.extname(entry.client_name) |> String.downcase()
          name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}#{ext}"
          File.cp!(tmp, Path.join(doc_dir, name))

          {:ok,
           %{
             binary: File.read!(tmp),
             mime: entry.client_type,
             url: "/uploads/animals/#{animal.id}/documents/#{name}",
             size: entry.client_size
           }}
        end)

      types =
        Animals.list_record_types()
        |> Enum.map(&%{slug: &1.slug, label: &1.label, category: &1.category})

      attach = Map.delete(file, :binary)

      {:noreply,
       socket
       |> assign(scan_loading: true, scan_error: nil)
       |> start_async(:scan, fn ->
         {RecordsAI.draft_from_file(
            animal,
            file.binary,
            file.mime,
            Date.utc_today(),
            types,
            presets
          ), attach}
       end)}
    else
      {:noreply, socket}
    end
  end

  # ── Records helpers (used by the template) ──

  @doc "A category's color from the loaded list (no query per row)."
  def cat_color(categories, slug) do
    case Enum.find(categories, &(&1.id == slug)) do
      nil -> "#6b7280"
      cat -> cat.color
    end
  end

  @doc "The category a record type belongs to."
  def type_category(types_by_cat, slug) do
    Enum.find_value(types_by_cat, fn {cat, types} ->
      if Enum.any?(types, &(&1.slug == slug)), do: cat
    end)
  end

  def due_text(days) when days < -1, do: "#{-days} days overdue"
  def due_text(-1), do: "1 day overdue"
  def due_text(0), do: "Due today"
  def due_text(1), do: "Due tomorrow"
  def due_text(days), do: "In #{days} days"

  def fmt_iso(nil), do: ""

  def fmt_iso(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> Calendar.strftime(d, "%b %-d, %Y")
      _ -> iso
    end
  end

  @doc "Records in the chosen category whose text matches the search."
  def filter_records(records, cat, query, type_labels) do
    q = query |> to_string() |> String.trim() |> String.downcase()

    records
    |> Enum.filter(&(cat == "" or &1.category == cat))
    |> Enum.filter(fn r ->
      q == "" or
        [r.title, r.description, r.notes, r.person, r.location, type_labels[r.record_type]]
        |> Enum.any?(&String.contains?(String.downcase(&1 || ""), q))
    end)
  end

  @doc "A color for a document type: its record type's category color when they match."
  def doc_color(doc_type, categories, types_by_cat) do
    t = String.downcase(doc_type || "")

    types_by_cat
    |> Enum.find_value(fn {cat, types} ->
      if Enum.any?(types, &(String.downcase(&1.label) == t or &1.slug == t)), do: cat
    end)
    |> case do
      nil ->
        palette = ~w(#6366f1 #2563eb #0891b2 #16a34a #d97706 #ec4899 #7c3aed #64748b)
        Enum.at(palette, :erlang.phash2(t, length(palette)))

      cat ->
        cat_color(categories, cat)
    end
  end

  # ── Visit helpers ──

  defp visit_item(preset, date) do
    interval = CarePreset.interval(preset)

    %{
      "preset_id" => preset.id,
      "label" => preset.label,
      "record_type" => preset.record_type,
      "title" => preset.title,
      "product" => preset.product || "",
      "date" => "",
      "days" => "",
      "next_due" => date_str(CareSchedule.next_due(interval, date)),
      "cost" => "",
      "interval" => interval,
      "due_touched" => false,
      "choices" => product_choices(preset)
    }
  end

  # One-tap product choices: dewormers used before plus common ones; for other types,
  # products used before (e.g. a vaccine brand).
  defp product_choices(%{record_type: "deworming", product: product}) do
    ([product] ++ Animals.recent_products("deworming") ++ CareSchedule.dewormers())
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.take(7)
  end

  defp product_choices(%{record_type: type}), do: Animals.recent_products(type, 4)

  # Form edits merged into the visit. When a date changes, next-due dates that weren't
  # typed by hand move with it.
  defp merge_visit(nil, _params, _target), do: nil

  defp merge_visit(visit, params, target) do
    visit = Map.merge(visit, Map.take(params, ~w(date person location notes)))
    item_params = params["items"] || %{}

    items =
      visit["items"]
      |> Enum.with_index()
      |> Enum.map(fn {item, i} ->
        ip = Map.get(item_params, "#{i}", %{})
        item = Map.merge(item, Map.take(ip, ~w(title product date next_due cost days)))

        idx = "#{i}"

        case target do
          ["visit", "items", ^idx, "next_due"] ->
            Map.put(item, "due_touched", true)

          # A date changed, or saving: next-due dates not typed by hand follow the dates.
          t when t == nil or (is_list(t) and length(t) > 1 and hd(tl(t)) in ["date", "items"]) ->
            if item["due_touched"], do: item, else: put_next_due(item, visit["date"])

          _ ->
            item
        end
      end)

    visit |> Map.put("items", items) |> Map.delete("error")
  end

  # Next due counts from when it's given (or starts), else the visit date.
  defp put_next_due(%{"interval" => nil} = item, _visit_date), do: item

  defp put_next_due(item, visit_date) do
    case parse_date(blank(item["date"]) || visit_date) do
      nil -> item
      from -> Map.put(item, "next_due", date_str(CareSchedule.next_due(item["interval"], from)))
    end
  end

  defp update_item(socket, i, fun) do
    visit = socket.assigns.visit
    assign(socket, :visit, Map.put(visit, "items", List.update_at(visit["items"], i, fun)))
  end

  defp save_visit_docs(socket, animal, visit) do
    doc_dir = Path.join([@uploads_dir, "animals", "#{animal.id}", "documents"])
    File.mkdir_p!(doc_dir)
    labels = Enum.map_join(visit["items"], ", ", & &1["label"])
    date = parse_date(visit["date"])
    title = "Vet visit #{if date, do: Calendar.strftime(date, "%b %-d, %Y")} (#{labels})"

    consume_uploaded_entries(socket, :visit_doc, fn %{path: tmp}, entry ->
      ext = Path.extname(entry.client_name)
      name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}#{ext}"
      File.cp!(tmp, Path.join(doc_dir, name))
      url = "/uploads/animals/#{animal.id}/documents/#{name}"

      Animals.create_document(%{
        animal_id: animal.id,
        title: String.slice(title, 0, 200),
        doc_type:
          if(Enum.any?(visit["items"], &(&1["record_type"] == "health_cert")),
            do: "Health Certificate",
            else: "Vet Record"
          ),
        doc_date: date,
        file_url: url,
        mime_type: entry.client_type,
        file_size: entry.client_size
      })

      {:ok, url}
    end)
  end

  # The vet or farrier named most recently, to save retyping it.
  defp last_person(records) do
    records
    |> Enum.find(&(&1.person not in [nil, ""] and &1.category == "health"))
    |> then(&((&1 && &1.person) || ""))
  end

  defp blank(v) when v in [nil, ""], do: nil
  defp blank(v), do: v

  defp date_str(nil), do: ""
  defp date_str(%Date{} = d), do: Date.to_iso8601(d)

  defp parse_date(s) do
    case Date.from_iso8601(to_string(s)) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  @doc "\"in 6 months\" / \"in 12 days\" / \"25 days overdue\" for the care card."
  def due_relative(days) when days < 0, do: due_text(days)
  def due_relative(days) when days > 75, do: "in #{round(days / 30.4)} months"
  def due_relative(days), do: due_text(days) |> String.replace("In ", "in ")

  # Asks Claude for record drafts from spoken words; they open in the visit form.
  defp start_voice_draft(socket, text) do
    %{animal: animal, presets: presets} = socket.assigns

    types =
      Animals.list_record_types()
      |> Enum.map(&%{slug: &1.slug, label: &1.label, category: &1.category})

    socket
    |> assign(rec_voice_text: text, rec_voice_loading: true, rec_voice_error: nil)
    |> start_async(:rec_draft, fn ->
      RecordsAI.draft(animal, text, Date.utc_today(), types, presets)
    end)
  end

  # Turns AI drafts (spoken or scanned) into the visit form, to check and edit.
  defp visit_from_drafts(drafts, presets, attach) do
    visit_date =
      drafts |> Enum.frequencies_by(& &1["date"]) |> Enum.max_by(&elem(&1, 1)) |> elem(0)

    items =
      Enum.map(drafts, fn d ->
        preset = CareSchedule.matching_preset(presets, d["record_type"], d["title"])

        %{
          "preset_id" => preset && preset.id,
          "label" => (preset && preset.label) || d["title"],
          "record_type" => d["record_type"],
          "title" => d["title"],
          "product" => d["description"] || "",
          "date" => if(d["date"] == visit_date, do: "", else: d["date"]),
          "days" => "",
          "next_due" => d["next_due_date"] || "",
          "cost" => if(d["cost"], do: to_string(d["cost"]), else: ""),
          "interval" => preset && CarePreset.interval(preset),
          "due_touched" => d["next_due_date"] != nil and not d["due_suggested"],
          "choices" =>
            product_choices(%{record_type: d["record_type"], product: d["description"]})
        }
      end)

    %{
      "date" => visit_date,
      "person" => Enum.find_value(drafts, "", & &1["person"]),
      "location" => Enum.find_value(drafts, "", & &1["location"]),
      "notes" => "",
      "items" => items,
      "attach" => attach
    }
  end

  # The product, plus the schedule when it runs several days:
  # "Panacur PowerPac · daily for 5 days, Oct 31 – Nov 4".
  defp describe(item, visit_date) do
    product = blank(item["product"])

    with {n, _} when n > 1 <- Integer.parse("#{item["days"]}"),
         %Date{} = start <- parse_date(blank(item["date"]) || visit_date) do
      stop = Date.add(start, n - 1)

      course =
        "daily for #{n} days, #{Calendar.strftime(start, "%b %-d")} – #{Calendar.strftime(stop, "%b %-d")}"

      Enum.join(Enum.reject([product, course], &is_nil/1), " · ")
    else
      _ -> product
    end
  end

  defp attach_scan(_animal, %{"attach" => nil}), do: :ok

  defp attach_scan(animal, %{"attach" => a} = visit) do
    date = parse_date(visit["date"])

    Animals.create_document(%{
      animal_id: animal.id,
      title: "Vet paperwork #{if date, do: Calendar.strftime(date, "%b %-d, %Y")}",
      doc_type:
        if(Enum.any?(visit["items"], &(&1["record_type"] == "health_cert")),
          do: "Health Certificate",
          else: "Vet Record"
        ),
      doc_date: date,
      file_url: a.url,
      mime_type: a.mime,
      file_size: a.size
    })
  end

  defp attach_scan(_animal, _visit), do: :ok

  defp open_data(socket, metric) do
    n = length(metric_points(socket.assigns.animal, metric))
    # Start by comparing the first and latest entries.
    assign(socket, data_metric: metric, data_pick: if(n >= 2, do: [0, n - 1], else: []))
  end

  # The logged entry behind a row in the growth list: the newest weight or height
  # event on that date (rows from records aren't edited here).
  defp entry_event(animal, metric, date) do
    with {:ok, d} <- Date.from_iso8601(date) do
      animal.timeline_events
      |> Enum.filter(&(&1.event_type == metric and &1.event_date == d))
      |> Enum.max_by(& &1.inserted_at, NaiveDateTime, fn -> nil end)
    else
      _ -> nil
    end
  end

  def metric_points(animal, "weight"), do: Insights.weights(animal.timeline_events, animal.records)
  def metric_points(animal, "height"), do: Insights.heights(animal.timeline_events, animal.records)

  @doc "A value in its unit: 792 lb, or 14.2 hh for a height in inches."
  def fmt_value("weight", v), do: "#{v} lb"
  def fmt_value("height", v), do: "#{Insights.hands(v)} hh"

  @doc "A change in its unit: +45 lb, +1.5 in."
  def fmt_change(_metric, nil), do: "–"
  def fmt_change("weight", v), do: "#{signed(v)} lb"
  def fmt_change("height", v), do: "#{signed(v * 1.0)} in"

  @doc "A rate per day as shown: lb/day for weight, inches a month for height."
  def fmt_rate(_metric, nil), do: "–"
  def fmt_rate("weight", per_day), do: "#{signed(per_day * 1.0)} lb/day"
  def fmt_rate("height", per_day), do: "#{signed(per_day * 30.4)} in/mo"

  @doc "+1.2 / -0.4 with the sign, for gains."
  def signed(nil), do: "–"
  def signed(n) when is_float(n), do: "#{if n >= 0, do: "+"}#{:erlang.float_to_binary(n, decimals: 1)}"
  def signed(n), do: "#{if n >= 0, do: "+"}#{n}"

  @paper_types [
    {"coggins", "Coggins"},
    {"health_cert", "Health certificate"},
    {"registration", "Registration"},
    {"brand_inspection", "Brand inspection"}
  ]

  @doc """
  The papers to show at a show or roping: the newest Coggins, health certificate,
  registration and brand inspection, in that order.
  """
  def papers(animal) do
    for {type, label} <- @paper_types,
        doc =
          animal.documents
          |> Enum.filter(&(paper_kind(&1) == type and is_binary(&1.file_url)))
          |> Enum.sort_by(&(&1.doc_date || NaiveDateTime.to_date(&1.inserted_at)), {:desc, Date})
          |> List.first(),
        doc != nil do
      %{
        id: doc.id,
        type: type,
        label: label,
        title: doc.title,
        url: doc.file_url,
        mime: doc.mime_type,
        date: doc.doc_date && Date.to_iso8601(doc.doc_date)
      }
    end
  end

  # Document types are names the ranch picks ("Coggins", "Health Certificate"), so
  # match on the words; untyped documents go by their title.
  defp paper_kind(doc) do
    text =
      case doc.doc_type do
        t when t in [nil, ""] -> doc.title
        t -> t
      end
      |> to_string()
      |> String.downcase()

    cond do
      text =~ ~r/coggins|\beia\b/ -> "coggins"
      text =~ ~r/health|\bcvi\b/ -> "health_cert"
      text =~ ~r/registration/ -> "registration"
      text =~ ~r/brand/ -> "brand_inspection"
      true -> nil
    end
  end

  @doc "When a photo was taken (or added, if no date was given)."
  def photo_date(photo), do: photo.taken_at || NaiveDateTime.to_date(photo.inserted_at)

  @doc "\"4 months apart\", \"12 days apart\" or \"Same day\"."
  def apart(a, b) do
    days = abs(Date.diff(a, b))

    cond do
      days == 0 -> "Same day"
      days < 60 -> "#{days} days apart"
      days < 730 -> "#{round(days / 30.4)} months apart"
      true -> "#{Float.round(days / 365.25, 1)} years apart"
    end
  end
end
