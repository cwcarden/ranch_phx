defmodule RanchPhxWeb.BackupLive.Index do
  @moduledoc "Off-site backups to Cloudflare R2: status, storage used, back up now, how to restore."
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1]
  alias RanchPhx.Backup

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Backups")
     |> assign(:running, false)
     |> load()}
  end

  defp load(socket) do
    files = Backup.local_files()

    {docs, other} =
      Enum.split_with(files, fn {rel, _} -> String.contains?(rel, "/documents/") end)

    runs = Backup.last_runs(10)

    socket
    |> assign(:configured, Backup.configured?())
    |> assign(:runs, runs)
    |> assign(:last_ok, Backup.last_ok())
    |> assign(:remote_bytes, Enum.find_value(runs, & &1.remote_bytes))
    |> assign(:docs, {length(docs), docs |> Enum.map(&elem(&1, 1)) |> Enum.sum()})
    |> assign(:other, {length(other), other |> Enum.map(&elem(&1, 1)) |> Enum.sum()})
  end

  @impl true
  def handle_event("run", _params, socket) do
    if socket.assigns.running or not socket.assigns.configured do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:running, true)
       |> start_async(:run, fn -> Backup.run("manual") end)}
    end
  end

  @impl true
  def handle_async(:run, {:ok, result}, socket) do
    socket = socket |> assign(:running, false) |> load()

    socket =
      case result do
        {:ok, %{status: "ok"} = r} ->
          put_flash(socket, :info, "Backed up. #{r.files_uploaded} new file(s) sent.")

        {:ok, r} ->
          put_flash(socket, :error, "Backup had a problem: #{r.error}")

        {:error, :busy} ->
          put_flash(socket, :info, "A backup is already running.")

        {:error, _} ->
          put_flash(socket, :error, "Backups aren't set up yet.")
      end

    {:noreply, socket}
  end

  def handle_async(:run, {:exit, _}, socket),
    do:
      {:noreply,
       socket
       |> assign(:running, false)
       |> put_flash(:error, "The backup stopped. Try again.")
       |> load()}

  def size(nil), do: "–"
  def size(b) when b < 1024, do: "#{b} B"
  def size(b) when b < 1024 * 1024, do: "#{Float.round(b / 1024, 1)} KB"
  def size(b) when b < 1024 * 1024 * 1024, do: "#{Float.round(b / 1024 / 1024, 1)} MB"
  def size(b), do: "#{Float.round(b / 1024 / 1024 / 1024, 2)} GB"

  def when_local(nil), do: "–"

  def when_local(%DateTime{} = utc) do
    local = RanchPhx.LocalTime.now(utc)
    today = RanchPhx.LocalTime.today()

    day =
      case Date.diff(today, NaiveDateTime.to_date(local)) do
        0 -> "Today"
        1 -> "Yesterday"
        _ -> Calendar.strftime(local, "%b %-d")
      end

    "#{day} at #{Calendar.strftime(local, "%-I:%M %p")}"
  end

  def percent(nil), do: 0
  def percent(b), do: min(100, Float.round(b / Backup.free_bytes() * 100, 1))
end
