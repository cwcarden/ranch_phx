defmodule RanchPhxWeb.AnimalReportController do
  use RanchPhxWeb, :controller
  alias RanchPhx.Animals
  alias RanchPhx.Animals.Record

  def show(conn, %{"id" => id} = params) do
    animal = Animals.get_animal_with_pedigree!(id)

    # A bare link (no choices) shows everything.
    any? = Enum.any?(~w(profile photos pedigree timeline records expenses documents weight hooves), &(params[&1] == "1"))
    params = if any?, do: params, else: Map.merge(params, Map.new(~w(profile photos pedigree timeline records expenses documents weight hooves), &{&1, "1"}))

    sections = %{
      profile:   params["profile"] == "1",
      photos:    params["photos"] == "1",
      pedigree:  params["pedigree"] == "1",
      timeline:  params["timeline"] == "1",
      records:   params["records"] == "1",
      expenses:  params["expenses"] == "1",
      documents: params["documents"] == "1",
      weight:    params["weight"] == "1",
      hooves:    params["hooves"] == "1"
    }

    record_cats = parse_list(params["record_cats"])
    date_from   = parse_date(params["from"])
    date_to     = parse_date(params["to"])

    # Picking Hoof Care records (and not every category) means "the hoof stuff":
    # bring in the hoof measurements and photos too.
    sections =
      if sections.records and "hoof_care" in record_cats and
           length(record_cats) < length(Record.categories()),
         do: %{sections | hooves: true},
         else: sections

    records =
      animal.records
      |> Enum.filter(fn r ->
        (record_cats == [] || r.category in record_cats) &&
        date_in_range?(r.date, date_from, date_to)
      end)
      |> Enum.group_by(& &1.category)
      |> then(fn by_cat ->
        Record.categories()
        |> Enum.filter(&Map.has_key?(by_cat, &1.id))
        |> Enum.map(fn cat ->
          rows = by_cat[cat.id] |> Enum.sort_by(& &1.date, {:desc, Date})
          {cat, rows}
        end)
      end)

    expense_records =
      animal.records
      |> Enum.filter(fn r ->
        r.cost != nil &&
        Decimal.compare(r.cost, Decimal.new("0")) != :lt &&
        date_in_range?(r.date, date_from, date_to)
      end)

    expense_by_cat =
      expense_records
      |> Enum.group_by(& &1.category)
      |> then(fn by_cat ->
        Record.categories()
        |> Enum.filter(&Map.has_key?(by_cat, &1.id))
        |> Enum.map(fn cat ->
          rows = by_cat[cat.id] |> Enum.sort_by(& &1.date, {:desc, Date})
          total = Enum.reduce(rows, Decimal.new("0"), fn r, acc -> Decimal.add(acc, r.cost) end)
          {cat, rows, total}
        end)
      end)

    expense_grand_total =
      Enum.reduce(expense_records, Decimal.new("0"), fn r, acc -> Decimal.add(acc, r.cost) end)

    pedigree_map = Animals.list_pedigree_entries(animal.id)

    weights =
      animal.timeline_events
      |> RanchPhx.Animals.Insights.weights(animal.records)
      |> Enum.filter(fn {d, _} -> date_in_range?(d, date_from, date_to) end)

    heights =
      animal.timeline_events
      |> RanchPhx.Animals.Insights.heights(animal.records)
      |> Enum.filter(fn {d, _} -> date_in_range?(d, date_from, date_to) end)

    hooves = hoof_report(animal, date_from, date_to)

    # The print layout is a whole page of its own; without the app's page around it,
    # the PDF maker isn't handed app styles it can't read.
    conn
    |> put_root_layout(false)
    |> put_layout(html: {RanchPhxWeb.Layouts, :print})
    |> render(:show,
        animal: animal,
        sections: sections,
        records: records,
        expense_by_cat: expense_by_cat,
        expense_grand_total: expense_grand_total,
        date_from: date_from,
        date_to: date_to,
        generated_at: RanchPhx.LocalTime.now(),
        report_title: report_title(animal, params["kind"]),
        kind: params["kind"],
        hooves: hooves,
        type_label_map: Animals.record_type_label_map(),
        pedigree_map: pedigree_map,
        weights: weights,
        heights: heights
      )
  end

  # ── Health record ──────────────────────────────────────────────────────────
  # One page you can hand a vet, buyer or show office: who the animal is, what's
  # current or due, and every vaccine, test, dewormer, medication and vet visit.

  @health_groups [
    {"Vaccinations", ~w(vaccination)},
    {"Coggins & lab tests", ~w(coggins lab_test)},
    {"Health certificates", ~w(health_cert travel_health_cert)},
    {"Deworming", ~w(deworming)},
    {"Medications & treatments", ~w(medication)},
    {"Vet exams, dental, injuries & surgery", ~w(vet_visit dental_float injury surgery)}
  ]

  def health(conn, %{"id" => id} = params) do
    alias RanchPhx.Animals.CareSchedule
    animal = Animals.get_animal_with_pedigree!(id)
    today = RanchPhx.LocalTime.today()
    from = parse_date(params["from"])
    to = parse_date(params["to"])
    grouped_types = @health_groups |> Enum.flat_map(&elem(&1, 1))

    health =
      Enum.filter(animal.records, fn r ->
        (r.category == "health" or r.record_type in grouped_types) and
          Date.compare(r.date, today) != :gt and date_in_range?(r.date, from, to)
      end)

    groups =
      (@health_groups ++ [{"Other health", nil}])
      |> Enum.map(fn
        {title, nil} -> {title, Enum.reject(health, &(&1.record_type in grouped_types))}
        {title, types} -> {title, Enum.filter(health, &(&1.record_type in types))}
      end)
      |> Enum.map(fn {t, rows} -> {t, Enum.sort_by(rows, &{Date.to_gregorian_days(&1.date), &1.id}, :desc)} end)
      |> Enum.reject(fn {_, rows} -> rows == [] end)

    status =
      animal.records
      |> Enum.filter(&(&1.category in ["health", "hoof_care"] or &1.record_type in grouped_types))
      |> CareSchedule.status(today)
      |> Enum.sort_by(& &1.days)

    hoof =
      animal.records
      |> Enum.filter(&(&1.category == "hoof_care" and Date.compare(&1.date, today) != :gt and date_in_range?(&1.date, from, to)))
      |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.id}, :desc)
      |> Enum.take(8)

    docs =
      animal.documents
      |> Enum.filter(fn d ->
        t = String.downcase("#{d.doc_type} #{d.title}")
        String.contains?(t, ["coggins", "health", "vet", "vaccin", "cvi", "lab", "rabies"])
      end)
      |> Enum.sort_by(&(&1.doc_date || ~D[1900-01-01]), {:desc, Date})

    weights =
      animal.timeline_events
      |> RanchPhx.Animals.Insights.weights(animal.records)
      |> Enum.sort_by(&elem(&1, 0), {:desc, Date})
      |> Enum.take(6)

    conn
    |> put_root_layout(false)
    |> put_layout(html: {RanchPhxWeb.Layouts, :print})
    |> render(:health,
      animal: animal,
      today: today,
      date_from: from,
      date_to: to,
      generated_at: RanchPhx.LocalTime.now(),
      report_title: "#{RanchPhx.Animals.Animal.display_name(animal)} health record",
      groups: groups,
      status: status,
      hoof: hoof,
      docs: docs,
      weights: weights,
      type_label_map: Animals.record_type_label_map()
    )
  end

  # The PDF is named "<title> report.pdf", so this one saves as "Asher farrier report.pdf".
  defp report_title(animal, "farrier"), do: "#{animal.name} farrier"
  defp report_title(animal, _), do: animal.name

  # Hoof measurements in the date range: the newest side and sole photo per foot with
  # what they mean, left/right pairs, and every measurement for the history table.
  defp hoof_report(animal, from, to) do
    alias RanchPhx.Animals.Hooves
    in_range = &date_in_range?(&1.date, from, to)
    sides = animal.timeline_events |> Hooves.measurements() |> Enum.filter(in_range)
    soles = animal.timeline_events |> Hooves.soles() |> Enum.filter(in_range)
    latest = Hooves.latest(sides)
    latest_sole = Hooves.latest(soles)

    feet =
      Hooves.feet()
      |> Enum.filter(fn {code, _} -> latest[code] || latest_sole[code] end)
      |> Enum.map(fn {code, name} ->
        side = latest[code]
        sole = latest_sole[code]

        %{
          code: code,
          name: name,
          side: side,
          side_summary:
            side &&
              Hooves.side_summary(code, side.toe, side.pastern, latest[Hooves.opposite(code)]),
          sole: sole,
          sole_summary: sole && Hooves.sole_summary(sole)
        }
      end)

    %{
      feet: feet,
      pairs: Hooves.pairs(latest),
      history: Enum.sort_by(sides ++ soles, &{&1.date, &1.inserted_at}, fn a, b -> a >= b end)
    }
  end

  defp parse_list(nil), do: []
  defp parse_list(list) when is_list(list), do: list
  defp parse_list(str) when is_binary(str), do: String.split(str, ",", trim: true)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp date_in_range?(nil, _from, _to), do: true
  defp date_in_range?(date, from, to) do
    (is_nil(from) || Date.compare(date, from) != :lt) &&
    (is_nil(to)   || Date.compare(date, to)   != :gt)
  end

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
end
