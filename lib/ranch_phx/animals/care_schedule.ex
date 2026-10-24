defmodule RanchPhx.Animals.CareSchedule do
  @moduledoc """
  Routine care: when each kind of care was last done, what was used, and when it's due.

  "Kind of care" groups records so the newest one wins: every deworming counts as one
  kind whatever the product, and a vaccination counts toward each disease it covers, so
  a Core EQ Innovator shot (EWT, West Nile and Rabies) satisfies all three.

  Intervals come from the quick-add presets (`RanchPhx.Animals.CarePreset`) and are
  starting points the owner can change, not veterinary advice.
  """
  alias RanchPhx.Animals.CarePreset

  # Words in a vaccination's title or details, and the diseases they mean.
  @vaccine_words [
    {"innovator", ["ewt", "west_nile", "rabies"]},
    {"vetera gold", ["ewt", "rhino_flu", "west_nile"]},
    {"west nile", ["west_nile"]},
    {"wnv", ["west_nile"]},
    {"vewt", ["ewt"]},
    {"ewt", ["ewt"]},
    {"eee", ["ewt"]},
    {"wee", ["ewt"]},
    {"tetanus", ["ewt"]},
    {"sleeping sickness", ["ewt"]},
    {"rhino", ["rhino_flu"]},
    {"flu", ["rhino_flu"]},
    {"influenza", ["rhino_flu"]},
    {"ehv", ["rhino_flu"]},
    {"rabies", ["rabies"]},
    {"strangles", ["strangles"]},
    {"dhpp", ["dhpp"]},
    {"distemper", ["dhpp"]},
    {"parvo", ["dhpp"]},
    {"bordetella", ["bordetella"]},
    {"kennel cough", ["bordetella"]}
  ]

  @disease_names %{
    "ewt" => "EWT / Tetanus",
    "west_nile" => "West Nile",
    "rhino_flu" => "Rhino / Flu",
    "rabies" => "Rabies",
    "strangles" => "Strangles",
    "dhpp" => "DHPP",
    "bordetella" => "Bordetella"
  }

  # Common dewormers, offered as one-tap choices along with ones used before.
  @dewormers [
    "Ivermectin",
    "Panacur PowerPac",
    "Quest Plus",
    "Safe-Guard",
    "Strongid",
    "Equimax",
    "Zimecterin Gold"
  ]

  def dewormers, do: @dewormers

  @doc "Next due date for an interval, from `date`."
  def next_due(nil, _date), do: nil

  def next_due({:months, n}, %Date{} = date) do
    total = date.year * 12 + date.month - 1 + n
    {year, month} = {div(total, 12), rem(total, 12) + 1}
    Date.new!(year, month, min(date.day, Calendar.ISO.days_in_month(year, month)))
  end

  def next_due({:weeks, n}, %Date{} = date), do: Date.add(date, n * 7)

  @doc "Diseases a vaccination covers, from its title and details (product)."
  def covers(record_type, title, details \\ nil)

  def covers("vaccination", title, details) do
    text = String.downcase("#{title} #{details}")

    @vaccine_words
    # A word must start a word ("rhino" matches "rhinopneumonitis", "wee" not "between").
    |> Enum.filter(fn {word, _} -> Regex.match?(~r/(?<![a-z])#{Regex.escape(word)}/, text) end)
    |> Enum.flat_map(&elem(&1, 1))
    |> Enum.uniq()
  end

  def covers(_type, _title, _details), do: []

  def disease_name(key), do: Map.get(@disease_names, key, key)

  @doc """
  The usual next-due date for a new record, from the presets for this kind of animal:
  for vaccinations, a preset covering the same diseases; otherwise a preset of the same
  type. Nil when no preset has an interval for it.
  """
  def suggested_due(presets, record_type, title, %Date{} = date) do
    case matching_preset(presets, record_type, title) do
      nil -> nil
      p -> next_due(CarePreset.interval(p), date)
    end
  end

  @doc "The preset a record of this type and title would come from, if any."
  def matching_preset(presets, record_type, title) do
    wanted = MapSet.new(covers(record_type, title))

    presets
    |> Enum.filter(&(&1.record_type == record_type))
    |> Enum.find(fn p ->
      record_type != "vaccination" or
        (MapSet.size(wanted) > 0 and
           MapSet.subset?(wanted, MapSet.new(covers(p.record_type, p.title, p.product))))
    end)
  end

  @doc """
  Every kind of care that has a next-due date, from the newest record of each kind,
  soonest first: `%{record, days, covers}`. `days` is negative when overdue; `covers`
  names the diseases a vaccination counts for. A combination vaccine that is the newest
  for several diseases appears once.
  """
  def status(records, %Date{} = today) do
    records
    |> Enum.reject(&(Date.compare(&1.date, today) == :gt))
    |> Enum.flat_map(fn r -> Enum.map(kinds(r), &{&1, r}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {_, rs} -> Enum.max_by(rs, &{Date.to_gregorian_days(&1.date), &1.id}) end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.filter(& &1.next_due_date)
    |> Enum.map(fn r ->
      %{
        record: r,
        days: Date.diff(r.next_due_date, today),
        covers: r.record_type |> covers(r.title, r.description) |> Enum.map(&disease_name/1)
      }
    end)
    |> Enum.sort_by(& &1.days)
  end

  @doc "Records dated after today (planned treatments), soonest first."
  def planned(records, %Date{} = today) do
    records
    |> Enum.filter(&(Date.compare(&1.date, today) == :gt))
    |> Enum.sort_by(&Date.to_gregorian_days(&1.date))
  end

  @doc "Only what's overdue or due within `days` days."
  def due(records, %Date{} = today, days \\ 45),
    do: records |> status(today) |> Enum.filter(&(&1.days <= days))

  defp kinds(%{record_type: "vaccination"} = r) do
    case covers("vaccination", r.title, r.description) do
      [] -> [{"vaccination", normalize(r.title)}]
      keys -> Enum.map(keys, &{"vaccine", &1})
    end
  end

  # One running schedule per type, whatever the product or wording.
  defp kinds(%{record_type: type})
       when type in ~w(deworming coggins dental_float trim shoeing health_cert),
       do: [{type}]

  defp kinds(r), do: [{r.record_type, normalize(r.title)}]

  defp normalize(title),
    do:
      title
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, " ")
      |> String.trim()
end
