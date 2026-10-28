defmodule RanchPhx.Push.Reminders do
  @moduledoc """
  The two reminders, in ranch time, following each person's Notifications settings:

    * morning (7 a.m. unless changed): treatment doses for today, care coming due
      (today, or up to two weeks ahead), and anything that just went overdue.
    * evening (6 p.m. unless changed): a nudge if a treatment dose isn't checked off.

  Each goes out once a day per person, only when there's something to say, and
  leaves out animals they've muted.
  """
  use GenServer
  alias RanchPhx.{Animals, LocalTime, Push}
  alias RanchPhx.Animals.CareSchedule
  alias RanchPhx.Push.Settings

  @check_every :timer.minutes(10)

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Process.send_after(self(), :tick, :timer.seconds(30))
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      run(LocalTime.now())
    rescue
      e ->
        require Logger
        Logger.error("Reminders failed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :tick, @check_every)
    {:noreply, state}
  end

  @doc "Sends whichever reminders are due at local time `now`, at most once a day each."
  def run(%NaiveDateTime{} = now) do
    today = NaiveDateTime.to_date(now)
    people = Push.people()

    if people != [] do
      rows = rows()

      for {settings, subs} <- people do
        if settings.morning_on and due?(now, settings.morning_hour),
          do:
            maybe_send(
              "morning:#{settings.user_id}:#{today}",
              subs,
              morning(rows, today, settings)
            )

        if settings.evening_on and due?(now, settings.evening_hour),
          do:
            maybe_send(
              "evening:#{settings.user_id}:#{today}",
              subs,
              evening(rows, today, settings)
            )
      end
    end

    :ok
  end

  # From the chosen hour until four hours after (so a restart doesn't miss it).
  defp due?(now, hour), do: now.hour >= hour and now.hour < hour + 4

  defp maybe_send(_key, _subs, nil), do: :nothing
  defp maybe_send(key, subs, msg), do: if(Push.first_time?(key), do: Push.notify(subs, msg))

  defp rows do
    animals = Animals.list_animals(status: "active")
    inputs = animals |> Enum.map(& &1.id) |> Animals.insight_inputs()
    Enum.map(animals, &{&1, get_in(inputs, [&1.id, :records]) || []})
  end

  @doc "The morning message for `[{animal, records}]`, or nil when nothing's due."
  def morning(rows, %Date{} = today, settings \\ %Settings{}) do
    lines =
      rows
      |> unmuted(settings)
      |> Enum.flat_map(fn {a, records} ->
        doses =
          if settings.doses do
            for c <- CareSchedule.active_courses(records, today), c.today_i, not c.today_given? do
              {a, "#{a.name}: #{c.record.title}, day #{c.today_i + 1} of #{c.total}"}
            end
          else
            []
          end

        care =
          for d <- CareSchedule.status(records, today),
              (settings.overdue and d.days == -1) or
                (settings.care and d.days >= 0 and d.days <= settings.care_days_ahead) do
            {a, "#{a.name}: #{d.record.title} #{when_text(d.days)}"}
          end

        doses ++ care
      end)

    case lines do
      [] ->
        nil

      [{a, line}] ->
        %{title: "Today at the ranch", body: line, url: "/animals/#{a.id}", tag: "morning"}

      many ->
        %{
          title: "Today at the ranch: #{length(many)} things",
          body: many |> Enum.map(&elem(&1, 1)) |> Enum.join("\n"),
          url: "/",
          tag: "morning"
        }
    end
  end

  @doc "The evening nudge: treatment doses not checked off today, or nil."
  def evening(rows, %Date{} = today, settings \\ %Settings{}) do
    missing =
      for {a, records} <- unmuted(rows, settings),
          settings.doses,
          c <- CareSchedule.active_courses(records, today),
          c.today_i,
          not c.today_given?,
          do: {a, c}

    case missing do
      [] ->
        nil

      [{a, c}] ->
        %{
          title: "#{a.name}'s #{c.record.title}",
          body: "Day #{c.today_i + 1} of #{c.total} isn't checked off yet. Given?",
          url: "/animals/#{a.id}",
          tag: "evening"
        }

      many ->
        %{
          title: "Doses not checked off today",
          body:
            Enum.map_join(many, "\n", fn {a, c} ->
              "#{a.name}: #{c.record.title}, day #{c.today_i + 1}"
            end),
          url: "/",
          tag: "evening"
        }
    end
  end

  defp when_text(-1), do: "overdue since yesterday"
  defp when_text(0), do: "due today"
  defp when_text(1), do: "due tomorrow"
  defp when_text(n), do: "due in #{n} days"

  defp unmuted(rows, settings),
    do: Enum.reject(rows, fn {a, _} -> a.id in settings.muted_animal_ids end)
end
