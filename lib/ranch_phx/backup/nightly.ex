defmodule RanchPhx.Backup.Nightly do
  @moduledoc """
  Runs the R2 backup once a night after 2 a.m. ranch time. If it fails, it tries
  again on the next check, up to three times that night.
  """
  use GenServer
  import Ecto.Query
  alias RanchPhx.{Backup, LocalTime, Repo}
  alias RanchPhx.Backup.Run

  @check_every :timer.minutes(10)
  @hour 2

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Process.send_after(self(), :tick, :timer.minutes(1))
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      Backup.clean_up_interrupted_once()
      if due?(LocalTime.now()), do: Backup.run("nightly")
    rescue
      e ->
        require Logger
        Logger.error("Nightly backup check failed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :tick, @check_every)
    {:noreply, state}
  end

  @doc "True when tonight's backup should run at local time `now`."
  def due?(%NaiveDateTime{} = now) do
    if Backup.configured?() and now.hour >= @hour do
      since =
        now
        |> NaiveDateTime.to_date()
        |> NaiveDateTime.new!(Time.new!(@hour, 0, 0))
        |> NaiveDateTime.add(-LocalTime.offset(DateTime.utc_now()), :second)
        |> DateTime.from_naive!("Etc/UTC")

      runs =
        Repo.all(
          from r in Run,
            where: r.trigger == "nightly" and r.started_at >= ^since,
            select: r.status
        )

      "ok" not in runs and "running" not in runs and length(runs) < 3
    else
      false
    end
  end
end
