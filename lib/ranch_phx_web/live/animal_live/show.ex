defmodule RanchPhxWeb.AnimalLive.Show do
  use RanchPhxWeb, :live_view
  alias RanchPhx.Animals
  alias RanchPhx.Animals.{Animal, TimelineEvent, Record}
  alias RanchPhx.Accounts.Scope
  require Decimal

  @uploads_dir Application.app_dir(:ranch_phx, "priv/static/uploads")

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    animal = Animals.get_animal_with_pedigree!(id)
    {:ok,
     socket
     |> assign(:animal, animal)
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
     |> allow_upload(:photo, accept: ~w(.jpg .jpeg .png .webp .gif .heic .heif), max_entries: 10, max_file_size: 20_000_000)
     |> allow_upload(:document, accept: ~w(.pdf .doc .docx .jpg .jpeg .png .txt), max_entries: 5, max_file_size: 50_000_000)
     |> allow_upload(:record_doc, accept: ~w(.pdf .doc .docx .jpg .jpeg .png .txt), max_entries: 5, max_file_size: 50_000_000)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

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
end
