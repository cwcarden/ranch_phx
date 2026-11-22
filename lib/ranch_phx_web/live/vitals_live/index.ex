defmodule RanchPhxWeb.VitalsLive.Index do
  @moduledoc """
  An animal's vitals: temperature chart with the normal range shaded, a quick form to
  log a reading, and a timeline of every reading by day (from the app, Siri, or the
  "say what was done" box).
  """
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1]
  alias RanchPhx.{Animals, LocalTime}
  alias RanchPhx.Accounts.Scope
  alias RanchPhx.Animals.{Animal, Vitals}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    animal = Animals.get_animal!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{Animal.display_name(animal)}'s vitals")
     |> assign(:animal, animal)
     |> assign(:ranges, Vitals.ranges(animal))
     |> assign(:is_superuser, Scope.superuser?(socket.assigns.current_scope))
     |> assign(:days, 14)
     |> assign(:show_form, false)
     |> fresh_form()
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, if(params["log"], do: assign(socket, :show_form, true), else: socket)}

  defp load(socket), do: assign(socket, :readings, Vitals.list(socket.assigns.animal.id))

  defp fresh_form(socket) do
    now = LocalTime.now()

    assign(
      socket,
      :form,
      to_form(
        %{
          "temp" => "",
          "pulse" => "",
          "resp" => "",
          "date" => Date.to_iso8601(NaiveDateTime.to_date(now)),
          "time" => now |> NaiveDateTime.to_time() |> Calendar.strftime("%H:%M"),
          "note" => ""
        },
        as: :v
      )
    )
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    socket = if socket.assigns.show_form, do: socket, else: fresh_form(socket)
    {:noreply, assign(socket, :show_form, !socket.assigns.show_form)}
  end

  def handle_event("days", %{"d" => d}, socket),
    do: {:noreply, assign(socket, :days, if(d == "all", do: :all, else: String.to_integer(d)))}

  def handle_event("save", %{"v" => p}, socket) do
    vitals = %{
      temp_f: temp(p["temp"]),
      pulse: int(p["pulse"], 10, 250),
      resp: int(p["resp"], 4, 120)
    }

    date =
      case Date.from_iso8601(p["date"] || ""),
        do: (
          {:ok, d} -> d
          _ -> LocalTime.today()
        )

    time =
      case Time.from_iso8601((p["time"] || "") <> ":00") do
        {:ok, t} -> t
        _ -> nil
      end

    cond do
      not socket.assigns.is_superuser ->
        {:noreply, socket}

      vitals.temp_f == nil and vitals.pulse == nil and vitals.resp == nil ->
        {:noreply,
         socket
         |> assign(:form, to_form(p, as: :v))
         |> put_flash(:error, "Enter a temperature, pulse or breathing rate.")}

      true ->
        note = p["note"] |> to_string() |> String.trim()

        {:ok, _} =
          Vitals.log(socket.assigns.animal, vitals,
            date: date,
            time: time,
            note: if(note == "", do: nil, else: note),
            source: "app"
          )

        {:noreply,
         socket
         |> load()
         |> fresh_form()
         |> assign(:show_form, false)
         |> put_flash(:info, Vitals.spoken(socket.assigns.animal, vitals))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with true <- socket.assigns.is_superuser,
         %{} = e <- Enum.find(socket.assigns.readings, &(to_string(&1.id) == id)),
         {:ok, _} <- Animals.delete_event(e) do
      {:noreply, socket |> load() |> put_flash(:info, "Deleted that reading.")}
    else
      _ -> {:noreply, socket}
    end
  end

  # 100.2 (°F), or 38.1 (°C, anything up to 45).
  defp temp(s) do
    case Float.parse(String.trim(to_string(s))) do
      {n, _} when n > 0 and n <= 45 -> Float.round(n * 9 / 5 + 32, 1)
      {n, _} when n >= 85 and n <= 110 -> Float.round(n, 1)
      _ -> nil
    end
  end

  defp int(s, lo, hi) do
    case Integer.parse(String.trim(to_string(s))) do
      {n, _} when n >= lo and n <= hi -> n
      _ -> nil
    end
  end

  # ── For the page ──

  def m(e, key), do: (e.metadata || %{})[key]

  @doc "Readings in the chosen window, oldest first, that have a temperature."
  def temp_points(readings, days) do
    cutoff = if days == :all, do: nil, else: Date.add(LocalTime.today(), -days)

    readings
    |> Enum.filter(
      &(m(&1, "temp_f") && (cutoff == nil or Date.compare(&1.event_date, cutoff) != :lt))
    )
    |> Enum.reverse()
  end

  def stamp(e) do
    t = e.event_time || ~T[12:00:00]
    NaiveDateTime.new!(e.event_date, t) |> NaiveDateTime.diff(~N[2000-01-01 00:00:00])
  end

  @w 340
  @h 170
  @pad_l 34
  @pad_r 10
  @pad_t 10
  @pad_b 22

  @doc "The chart: `%{pts, band, ymin, ymax, ticks, x0, x1}` or nil with no readings."
  def chart([], _range), do: nil

  def chart(points, range) do
    temps = Enum.map(points, &m(&1, "temp_f"))
    {lo, hi} = range || {Enum.min(temps), Enum.max(temps)}
    ymin = Float.floor(min(lo - 0.5, Enum.min(temps) - 0.3) * 1.0)
    ymax = Float.ceil(max(hi + 0.5, Enum.max(temps) + 0.3) * 1.0)
    s0 = points |> hd() |> stamp()
    s1 = points |> List.last() |> stamp()
    span = max(s1 - s0, 1)

    x = fn e ->
      if length(points) == 1,
        do: (@pad_l + @w - @pad_r) / 2,
        else: @pad_l + (stamp(e) - s0) / span * (@w - @pad_l - @pad_r)
    end

    y = fn t -> @pad_t + (ymax - t) / (ymax - ymin) * (@h - @pad_t - @pad_b) end

    %{
      w: @w,
      h: @h,
      pad_l: @pad_l,
      pad_r: @pad_r,
      pts:
        Enum.map(
          points,
          &%{x: Float.round(x.(&1) * 1.0, 1), y: Float.round(y.(m(&1, "temp_f")) * 1.0, 1), e: &1}
        ),
      band: range && %{y: Float.round(y.(hi), 1), h: Float.round(y.(lo) - y.(hi), 1)},
      ticks:
        for(
          t <- tick_values(ymin, ymax),
          do: %{y: Float.round(y.(t), 1), label: :erlang.float_to_binary(t * 1.0, decimals: 0)}
        ),
      first: hd(points).event_date,
      last: List.last(points).event_date,
      base: @h - @pad_b
    }
  end

  defp tick_values(ymin, ymax) do
    step = if ymax - ymin > 6, do: 2.0, else: 1.0
    Stream.iterate(Float.ceil(ymin), &(&1 + step)) |> Enum.take_while(&(&1 <= ymax))
  end

  def day_label(d) do
    today = LocalTime.today()

    cond do
      d == today -> "Today"
      d == Date.add(today, -1) -> "Yesterday"
      true -> Calendar.strftime(d, "%a, %b %-d")
    end
  end

  def time_label(nil), do: nil
  def time_label(t), do: Calendar.strftime(t, "%-I:%M %p")

  def status_class(nil), do: ""
  def status_class(:normal), do: "ok"
  def status_class(:high), do: "high"
  def status_class(:low), do: "low"

  def range_text({lo, hi}) when is_float(lo),
    do: "#{:erlang.float_to_binary(lo, decimals: 1)}–#{:erlang.float_to_binary(hi, decimals: 1)}"

  def range_text({lo, hi}), do: "#{lo}–#{hi}"
end
