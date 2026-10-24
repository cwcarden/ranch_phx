defmodule RanchPhx.Animals do
  import Ecto.Query
  alias RanchPhx.Repo
  alias RanchPhx.Animals.{Animal, TimelineEvent, Record, Genetics, Document, DocType, Photo, RecordType, RecordCategory, PedigreeEntry, CarePreset}

  # ── Animals ────────────────────────────────────────────────────────────────

  def list_animals(opts \\ []) do
    query = from a in Animal, where: a.owned == true, order_by: [asc: a.kind, asc: a.name]
    query
    |> filter_kind(opts[:kind])
    |> filter_status(opts[:status])
    |> filter_search(opts[:search])
    |> Repo.all()
  end

  @doc """
  What the animal cards need for their insights, for many animals in a few queries:
  `%{animal_id => %{events: weight events, records: records}}`.
  """
  def insight_inputs([]), do: %{}

  def insight_inputs(ids) do
    events =
      Repo.all(from e in TimelineEvent, where: e.animal_id in ^ids and e.event_type == "weight")
      |> Enum.group_by(& &1.animal_id)

    records = Repo.all(from r in Record, where: r.animal_id in ^ids) |> Enum.group_by(& &1.animal_id)

    Map.new(ids, &{&1, %{events: Map.get(events, &1, []), records: Map.get(records, &1, [])}})
  end

  def list_all_animals_for_pedigree(search \\ nil) do
    base = from a in Animal, order_by: [asc: a.name]
    if search && search != "" do
      pat = "%#{search}%"
      where(base, [a], ilike(a.name, ^pat) or ilike(a.registration_number, ^pat))
    else
      base
    end
    |> Repo.all()
  end

  def get_animal!(id), do: Repo.get!(Animal, id)

  def get_animal_with_pedigree!(id) do
    Repo.get!(Animal, id)
    |> Repo.preload([:sire, :dam, :photos, genetics: [], documents: [], timeline_events: [],
                     records: from(r in Record, order_by: [desc: r.date, desc: r.inserted_at])])
    |> load_sire_parents()
    |> load_dam_parents()
  end

  def create_animal(attrs) do
    %Animal{}
    |> Animal.changeset(attrs)
    |> Repo.insert()
  end

  def update_animal(%Animal{} = animal, attrs) do
    animal
    |> Animal.changeset(attrs)
    |> Repo.update()
  end

  def delete_animal(%Animal{} = animal), do: Repo.delete(animal)

  def change_animal(%Animal{} = animal, attrs \\ %{}), do: Animal.changeset(animal, attrs)

  # ── Pedigree helpers ────────────────────────────────────────────────────────

  defp load_sire_parents(%Animal{sire: %Animal{} = sire} = animal) do
    sire_loaded = Repo.preload(sire, [:sire, :dam])
    %{animal | sire: sire_loaded}
  end
  defp load_sire_parents(animal), do: animal

  defp load_dam_parents(%Animal{dam: %Animal{} = dam} = animal) do
    dam_loaded = Repo.preload(dam, [:sire, :dam])
    %{animal | dam: dam_loaded}
  end
  defp load_dam_parents(animal), do: animal

  def pedigree_ancestors(%Animal{} = animal, depth \\ 4) do
    build_pedigree(animal.id, depth)
  end

  defp build_pedigree(nil, _depth), do: nil
  defp build_pedigree(_id, 0), do: nil
  defp build_pedigree(id, depth) do
    case Repo.get(Animal, id) do
      nil -> nil
      a ->
        %{animal: a, sire: build_pedigree(a.sire_id, depth - 1), dam: build_pedigree(a.dam_id, depth - 1)}
    end
  end

  # ── Records ────────────────────────────────────────────────────────────────

  def list_records(animal_id) do
    from(r in Record,
      where: r.animal_id == ^animal_id,
      order_by: [desc: r.date, desc: r.inserted_at]
    )
    |> Repo.all()
  end

  def create_record(attrs) do
    %Record{}
    |> Record.changeset(attrs)
    |> Repo.insert()
  end

  def update_record(%Record{} = record, attrs) do
    record |> Record.changeset(attrs) |> Repo.update()
  end

  def delete_record(%Record{} = record), do: Repo.delete(record)

  def change_record(%Record{} = record, attrs \\ %{}), do: Record.changeset(record, attrs)

  # ── Timeline ───────────────────────────────────────────────────────────────

  def list_timeline(animal_id) do
    from(e in TimelineEvent,
      where: e.animal_id == ^animal_id,
      order_by: [desc: e.event_date, desc: e.inserted_at]
    )
    |> Repo.all()
  end

  def create_event(attrs) do
    %TimelineEvent{}
    |> TimelineEvent.changeset(attrs)
    |> Repo.insert()
  end

  def delete_event(%TimelineEvent{} = event), do: Repo.delete(event)

  # ── Genetics ───────────────────────────────────────────────────────────────

  def list_genetics(animal_id) do
    from(g in Genetics, where: g.animal_id == ^animal_id, order_by: [desc: g.inserted_at])
    |> Repo.all()
  end

  def create_genetics(attrs) do
    %Genetics{}
    |> Genetics.changeset(attrs)
    |> Repo.insert()
  end

  def update_genetics(%Genetics{} = g, attrs) do
    g |> Genetics.changeset(attrs) |> Repo.update()
  end

  def delete_genetics(%Genetics{} = g), do: Repo.delete(g)

  # ── Documents ──────────────────────────────────────────────────────────────

  def list_documents(animal_id) do
    from(d in Document, where: d.animal_id == ^animal_id, order_by: [desc: d.inserted_at])
    |> Repo.all()
  end

  def create_document(attrs) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  def delete_document(%Document{} = d), do: Repo.delete(d)

  # ── Document Types ─────────────────────────────────────────────────────────

  def list_doc_types do
    from(d in DocType, order_by: [asc: d.position, asc: d.name]) |> Repo.all()
  end

  def create_doc_type(attrs) do
    count = Repo.aggregate(DocType, :count)
    %DocType{}
    |> DocType.changeset(Map.put(attrs, "position", count))
    |> Repo.insert()
  end

  def delete_doc_type(%DocType{} = dt), do: Repo.delete(dt)

  # ── Photos ─────────────────────────────────────────────────────────────────

  def list_photos(animal_id) do
    from(p in Photo, where: p.animal_id == ^animal_id, order_by: [desc: p.taken_at, desc: p.inserted_at])
    |> Repo.all()
  end

  def create_photo(attrs) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
  end

  def delete_photo(%Photo{} = p), do: Repo.delete(p)

  def set_cover_photo(animal_id, photo_id) do
    Repo.transaction(fn ->
      from(p in Photo, where: p.animal_id == ^animal_id) |> Repo.update_all(set: [is_cover: false])
      from(p in Photo, where: p.id == ^photo_id) |> Repo.update_all(set: [is_cover: true])
      cover = Repo.get!(Photo, photo_id)
      from(a in Animal, where: a.id == ^animal_id) |> Repo.update_all(set: [cover_photo_url: cover.url])
    end)
  end

  # ── Pedigree ───────────────────────────────────────────────────────────────

  def list_pedigree_entries(animal_id) do
    from(pe in PedigreeEntry, where: pe.animal_id == ^animal_id)
    |> Repo.all()
    |> Map.new(fn pe -> {pe.slot, pe} end)
  end

  def get_pedigree_entry!(id), do: Repo.get!(PedigreeEntry, id)

  def upsert_pedigree_entry(attrs) do
    animal_id = Map.get(attrs, :animal_id) || Map.get(attrs, "animal_id")
    slot      = Map.get(attrs, :slot)      || Map.get(attrs, "slot")

    (Repo.get_by(PedigreeEntry, animal_id: animal_id, slot: slot) || %PedigreeEntry{})
    |> PedigreeEntry.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def delete_pedigree_entry(%PedigreeEntry{} = pe), do: Repo.delete(pe)

  # ── Record Types ───────────────────────────────────────────────────────────

  # ── Care presets (quick-add buttons) ──

  @doc "Quick-add buttons for a kind of animal (horse, dog, or anything else)."
  def list_care_presets(kind) do
    kind = CarePreset.kind_for(kind)

    from(p in CarePreset, where: p.kind == ^kind, order_by: [asc: p.position, asc: p.id])
    |> Repo.all()
  end

  def get_care_preset!(id), do: Repo.get!(CarePreset, id)
  def change_care_preset(%CarePreset{} = p, attrs \\ %{}), do: CarePreset.changeset(p, attrs)

  def create_care_preset(kind, attrs) do
    kind = CarePreset.kind_for(kind)
    next = Repo.aggregate(from(p in CarePreset, where: p.kind == ^kind), :count)

    %CarePreset{kind: kind, position: next}
    |> CarePreset.changeset(attrs)
    |> Repo.insert()
  end

  def update_care_preset(%CarePreset{} = p, attrs),
    do: p |> CarePreset.changeset(attrs) |> Repo.update()

  def delete_care_preset(%CarePreset{} = p), do: Repo.delete(p)

  @doc "Products used before for a record type on any animal, most recent first."
  def recent_products(record_type, limit \\ 6) do
    from(r in Record,
      where: r.record_type == ^record_type and not is_nil(r.description) and r.description != "",
      group_by: r.description,
      order_by: [desc: max(r.date)],
      limit: ^(limit * 3),
      select: r.description
    )
    |> Repo.all()
    # "Panacur PowerPac · daily for 5 days, …" is the product Panacur PowerPac.
    |> Enum.map(&(&1 |> String.split(" · ") |> hd() |> String.trim()))
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.take(limit)
  end

  def list_record_types do
    from(rt in RecordType, order_by: [asc: rt.position, asc: rt.label])
    |> Repo.all()
  end

  def list_record_types_by_category do
    list_record_types() |> Enum.group_by(& &1.category)
  end

  def record_type_label_map do
    list_record_types() |> Map.new(fn rt -> {rt.slug, rt.label} end)
  end

  def get_record_type!(id), do: Repo.get!(RecordType, id)

  def create_record_type(attrs) do
    %RecordType{} |> RecordType.changeset(attrs) |> Repo.insert()
  end

  def update_record_type(%RecordType{} = rt, attrs) do
    rt |> RecordType.changeset(attrs) |> Repo.update()
  end

  def delete_record_type(%RecordType{} = rt), do: Repo.delete(rt)

  # ── Record Categories ──────────────────────────────────────────────────────

  def list_categories do
    from(rc in RecordCategory, order_by: [asc: rc.position, asc: rc.label])
    |> Repo.all()
  end

  def get_category!(id), do: Repo.get!(RecordCategory, id)

  def create_category(attrs) do
    %RecordCategory{} |> RecordCategory.changeset(attrs) |> Repo.insert()
  end

  def update_category(%RecordCategory{} = rc, attrs) do
    rc |> RecordCategory.changeset(attrs) |> Repo.update()
  end

  def delete_category(%RecordCategory{} = rc), do: Repo.delete(rc)

  # ── Private filters ────────────────────────────────────────────────────────

  defp filter_kind(query, nil), do: query
  defp filter_kind(query, ""), do: query
  defp filter_kind(query, kind), do: where(query, [a], a.kind == ^kind)

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query
  defp filter_status(query, status), do: where(query, [a], a.status == ^status)

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query
  defp filter_search(query, q) do
    where(query, [a], ilike(a.name, ^"%#{q}%") or ilike(a.registration_number, ^"%#{q}%"))
  end
end
