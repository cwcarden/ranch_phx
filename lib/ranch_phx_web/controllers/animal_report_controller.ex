defmodule RanchPhxWeb.AnimalReportController do
  use RanchPhxWeb, :controller
  alias RanchPhx.Animals
  alias RanchPhx.Animals.Record

  def show(conn, %{"id" => id} = params) do
    animal = Animals.get_animal_with_pedigree!(id)

    sections = %{
      profile:   params["profile"] == "1",
      photos:    params["photos"] == "1",
      pedigree:  params["pedigree"] == "1",
      timeline:  params["timeline"] == "1",
      records:   params["records"] == "1",
      expenses:  params["expenses"] == "1",
      documents: params["documents"] == "1"
    }

    record_cats = parse_list(params["record_cats"])
    date_from   = parse_date(params["from"])
    date_to     = parse_date(params["to"])

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

    conn
    |> put_layout(html: {RanchPhxWeb.Layouts, :print})
    |> render(:show,
        animal: animal,
        sections: sections,
        records: records,
        expense_by_cat: expense_by_cat,
        expense_grand_total: expense_grand_total,
        date_from: date_from,
        date_to: date_to,
        generated_at: DateTime.utc_now(),
        report_title: animal.name,
        type_label_map: Animals.record_type_label_map(),
        pedigree_map: pedigree_map
      )
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
