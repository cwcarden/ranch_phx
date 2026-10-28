defmodule RanchPhx.Push.Reminders do
  @moduledoc """
  The two reminders, in ranch time:

    * 7 a.m. – what needs doing today: treatment doses (Panacur day 2 of 5), care due
      today or tomorrow, and anything that just went overdue.
    * 6 p.m. – a nudge if a treatment dose still isn't checked off today.

  Each goes out once a day, and only when there's something to say.
  """
  use GenServer
  alias RanchPhx.{Animals, LocalTime, Push}
  alias RanchPhx.Animals.CareSchedule

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

  @doc "Sends whichever reminder is due at local time `now`, at most once a day each."
  def run(%NaiveDateTime{} = now) do
    today = NaiveDateTime.to_date(now)

    cond do
      now.hour >= 7 and now.hour < 12 -> maybe_send("morning:#{today}", morning(rows(), today))
      now.hour >= 18 and now.hour < 22 -> maybe_send("evening:#{today}", evening(rows(), today))
      true -> :nothing
    end
  end

  defp maybe_send(_key, nil), do: :nothing

  defp maybe_send(key, msg) do
    case Push.all_devices() do
      [] -> :nothing
      subs -> if Push.first_time?(key), do: Push.notify(subs, msg), else: :already_sent
    end
  end

  defp rows do
    animals = Animals.list_animals(status: "active")
    inputs = animals |> Enum.map(& &1.id) |> Animals.insight_inputs()
    Enum.map(animals, &{&1, get_in(inputs, [&1.id, :records]) || []})
  end

  @doc "The morning message for `[{animal, records}]`, or nil when nothing's due."
  def morning(rows, %Date{} = today) do
    lines =
      Enum.flat_map(rows, fn {a, records} ->
        doses =
          for c <- CareSchedule.active_courses(records, today), c.today_i, not c.today_given? do
            {a, "#{a.name}: #{c.record.title}, day #{c.today_i + 1} of #{c.total}"}
          end

        care =
          for d <- CareSchedule.status(records, today), d.days in [-1, 0, 1] do
            when_ =
              %{-1 => "overdue since yesterday", 0 => "due today", 1 => "due tomorrow"}[d.days]

            {a, "#{a.name}: #{d.record.title} #{when_}"}
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
  def evening(rows, %Date{} = today) do
    missing =
      for {a, records} <- rows,
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
end
