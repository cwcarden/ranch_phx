defmodule RanchPhx.Animals.CareSchedule do
  @moduledoc """
  Routine care: one-tap presets for common records (West Nile, deworming, Coggins…),
  the usual interval to the next one, and what's due or overdue for an animal.

  Intervals are common starting points, not veterinary advice; the next-due date is
  always shown so it can be changed to whatever the vet recommends.
  """

  # {key, button label, record type slug, title, interval}
  @horse [
    {"west_nile", "West Nile", "vaccination", "West Nile vaccine", {:months, 12}},
    {"ewt", "EWT / Tetanus", "vaccination", "EEE/WEE/Tetanus vaccine", {:months, 12}},
    {"rhino_flu", "Rhino / Flu", "vaccination", "Rhino/Flu vaccine", {:months, 6}},
    {"rabies", "Rabies", "vaccination", "Rabies vaccine", {:months, 12}},
    {"strangles", "Strangles", "vaccination", "Strangles vaccine", {:months, 12}},
    {"deworming", "Deworming", "deworming", "Deworming", {:months, 3}},
    {"coggins", "Coggins", "coggins", "Coggins test", {:months, 12}},
    {"trim", "Trim", "trim", "Hoof trim", {:weeks, 6}},
    {"shoeing", "Shoes", "shoeing", "Shoeing", {:weeks, 6}},
    {"dental", "Dental", "dental_float", "Dental float", {:months, 12}}
  ]

  @dog [
    {"rabies", "Rabies", "vaccination", "Rabies vaccine", {:months, 12}},
    {"dhpp", "DHPP", "vaccination", "DHPP vaccine", {:months, 12}},
    {"bordetella", "Bordetella", "vaccination", "Bordetella vaccine", {:months, 12}},
    {"deworming", "Deworming", "deworming", "Deworming", {:months, 3}},
    {"heartworm", "Heartworm", "medication", "Heartworm prevention", {:months, 1}},
    {"vet_visit", "Vet visit", "vet_visit", "Wellness exam", {:months, 12}}
  ]

  @other [
    {"vaccination", "Vaccination", "vaccination", "Vaccination", {:months, 12}},
    {"deworming", "Deworming", "deworming", "Deworming", {:months, 3}},
    {"vet_visit", "Vet visit", "vet_visit", "Vet visit", nil}
  ]

  @doc """
  Quick-add presets for an animal kind, keeping only record types that still exist
  (`type_slugs`), as maps with `:key, :label, :record_type, :title, :interval`.
  """
  def presets(kind, type_slugs) do
    kind
    |> presets_for()
    |> Enum.filter(fn {_, _, type, _, _} -> type in type_slugs end)
    |> Enum.map(fn {key, label, type, title, interval} ->
      %{key: key, label: label, record_type: type, title: title, interval: interval}
    end)
  end

  @doc "Next due date for a preset's interval, from `date`."
  def next_due(nil, _date), do: nil

  def next_due({:months, n}, %Date{} = date) do
    total = date.year * 12 + date.month - 1 + n
    {year, month} = {div(total, 12), rem(total, 12) + 1}
    Date.new!(year, month, min(date.day, Calendar.ISO.days_in_month(year, month)))
  end

  def next_due({:weeks, n}, %Date{} = date), do: Date.add(date, n * 7)

  # Words that identify each vaccine in a title, so "WNV booster" counts as West Nile.
  @vaccine_words %{
    "west_nile" => ["west nile", "wnv"],
    "ewt" => ["eee", "wee", "tetanus", "ewt", "4-way", "5-way", "sleeping sickness"],
    "rhino_flu" => ["rhino", "flu", "influenza", "ehv"],
    "rabies" => ["rabies"],
    "strangles" => ["strangles"],
    "dhpp" => ["dhpp", "distemper", "parvo"],
    "bordetella" => ["bordetella", "kennel cough"]
  }

  @doc """
  The usual next-due date for a record of `record_type` titled `title`, done on `date`,
  for an animal of `kind`, or nil when there's no usual interval. Vaccinations need a
  title that names the vaccine; other types (deworming, Coggins, trim…) match by type.
  """
  def suggested_due(kind, record_type, title, %Date{} = date) do
    title = String.downcase(title || "")

    kind
    |> presets_for()
    |> Enum.find(fn {key, _, type, _, _} ->
      type == record_type and
        (type != "vaccination" or
           Enum.any?(Map.get(@vaccine_words, key, []), &String.contains?(title, &1)))
    end)
    |> case do
      {_, _, _, _, interval} -> next_due(interval, date)
      nil -> nil
    end
  end

  defp presets_for("horse"), do: @horse
  defp presets_for("dog"), do: @dog
  defp presets_for(_), do: @other

  @doc """
  What's due within `days` days or already overdue, soonest first. Only the most
  recent record of each kind counts: last year's West Nile shot isn't overdue once
  this year's is logged. Returns `%{record, days}` (negative days = overdue).
  """
  def due(records, %Date{} = today, days \\ 45) do
    records
    |> Enum.group_by(&{&1.record_type, normalize(&1.title)})
    |> Enum.map(fn {_, rs} -> Enum.max_by(rs, &Date.to_gregorian_days(&1.date)) end)
    |> Enum.filter(&(&1.next_due_date && Date.diff(&1.next_due_date, today) <= days))
    |> Enum.map(&%{record: &1, days: Date.diff(&1.next_due_date, today)})
    |> Enum.sort_by(& &1.days)
  end

  defp normalize(title),
    do:
      title
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, " ")
      |> String.trim()
end
