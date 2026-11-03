defmodule RanchPhx.FeedPlans do
  @moduledoc "Feed plans: one per animal, editable in the app and shareable by link."
  import Ecto.Query
  alias RanchPhx.Repo
  alias RanchPhx.FeedPlans.FeedPlan

  @doc "Where a new plan starts: the usual headings, empty, to fill in or delete."
  def starter_sections do
    [
      %{"title" => "Morning feed", "body" => ""},
      %{"title" => "Evening feed", "body" => ""},
      %{"title" => "Hay", "body" => ""},
      %{"title" => "Water", "body" => ""},
      %{"title" => "Supplements", "body" => ""},
      %{"title" => "Stall and bedding", "body" => ""},
      %{"title" => "Other notes", "body" => ""},
      %{"title" => "Emergency contacts", "body" => ""}
    ]
  end

  @doc "The animal's plan, or nil."
  def get_for_animal(animal_id), do: Repo.get_by(FeedPlan, animal_id: animal_id)

  @doc "The animal's plan, or an unsaved new one with the starter headings."
  def get_or_new(animal_id) do
    get_for_animal(animal_id) || %FeedPlan{animal_id: animal_id, sections: starter_sections()}
  end

  @doc "Saves the sections (creating the plan the first time)."
  def save(%FeedPlan{} = plan, sections) do
    plan
    |> ensure_token()
    |> FeedPlan.changeset(%{sections: sections})
    |> Repo.insert_or_update()
  end

  @doc "Turns the share link on or off (saving the plan first if it's new)."
  def set_sharing(%FeedPlan{} = plan, on?) when is_boolean(on?) do
    plan
    |> ensure_token()
    |> Ecto.Changeset.change(share_on: on?)
    |> Repo.insert_or_update()
  end

  @doc "A new secret link; the old one stops working."
  def new_link(%FeedPlan{id: id} = plan) when not is_nil(id) do
    plan |> Ecto.Changeset.change(share_token: token()) |> Repo.update()
  end

  @doc "The plan behind a shared link, only while sharing is on."
  def get_shared(token) when is_binary(token) and byte_size(token) >= 20 do
    Repo.one(
      from p in FeedPlan, where: p.share_token == ^token and p.share_on == true, preload: :animal
    )
  end

  def get_shared(_), do: nil

  @doc "Sections with something written in them, for showing and printing."
  def filled(%FeedPlan{sections: sections}),
    do: Enum.filter(sections || [], &(String.trim(&1["body"] || "") != ""))

  @doc """
  A section's text as lines, each split into a bold lead and the rest when it starts
  with a short label and a colon ("Where to find it: white feed bin").
  """
  def lines(body) do
    body
    |> to_string()
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case Regex.run(~r/^([^:]{1,40}):\s+(.+)$/u, line) do
        [_, label, rest] -> {label, rest}
        _ -> {nil, line}
      end
    end)
  end

  @doc """
  Treatments running now (from the animal's daily reminders: medicine, dewormer, daily
  care like soaking a foot), as lines for the plan. Added automatically, so the plan and
  its link always match what's in the app. `[{label, text}]`.
  """
  def current_care(animal_id, today \\ RanchPhx.LocalTime.today()) do
    alias RanchPhx.Animals.CareSchedule

    RanchPhx.Animals.get_animal_with_pedigree!(animal_id).records
    |> CareSchedule.active_courses(today)
    |> Enum.reject(&(&1.finished? or Date.compare(List.last(&1.dates), today) == :lt))
    |> Enum.flat_map(fn c ->
      last = List.last(c.dates)
      first = hd(c.dates)

      when_text =
        cond do
          Date.compare(first, today) == :gt ->
            "starts #{fmt(first)}, daily through #{fmt(last)} (#{c.total} days)"

          last == today ->
            "today is the last day (day #{c.total} of #{c.total})"

          true ->
            "daily through #{fmt(last)} (day #{(c.today_i || 0) + 1} of #{c.total} today)"
        end

      details =
        [CareSchedule.describe(c.record.description, c.record.date), c.record.notes]
        |> Enum.map(&String.trim(to_string(&1 || "")))
        |> Enum.reject(&(&1 == "" or &1 =~ ~r/^daily for \d+ days?$/i))
        |> Enum.map(&String.replace(&1, ~r/\s*·?\s*daily for \d+ days?/i, ""))
        |> Enum.reject(&(&1 == ""))

      [{c.record.title, when_text} | Enum.map(details, &{nil, &1})]
    end)
  end

  defp fmt(d), do: Calendar.strftime(d, "%a %b %-d")

  defp ensure_token(%FeedPlan{share_token: nil} = plan), do: %{plan | share_token: token()}
  defp ensure_token(plan), do: plan

  defp token, do: :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
end
