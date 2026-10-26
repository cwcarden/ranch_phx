defmodule RanchPhxWeb.TrainingTimeline do
  @moduledoc """
  The Timeline card on a training book: the whole program as a colored bar, a
  closer look at the months around today with logged days and goals, day counts,
  and an optional weekly activity chart. Drawn as inline SVG, no chart library.
  """
  use Phoenix.Component
  import RanchPhxWeb.TrainingComponents, only: [section_head: 1, countdown: 1]
  alias RanchPhx.Training.Timeline

  # SVG coordinate width; everything scales to the card width.
  @w 340

  attr :tl, :map, required: true
  attr :today, Date, required: true
  attr :show_weeks, :boolean, default: false

  def timeline_card(assigns) do
    assigns =
      assigns
      |> assign(:overview, overview(assigns.tl, assigns.today))
      |> assign(:zoom, zoom(assigns.tl, assigns.today))
      |> assign(:upcoming, upcoming(assigns.tl, assigns.today))
      |> assign(:chart, week_chart(assigns.tl))
      |> assign(:w, @w)

    ~H"""
    <div class="tr-card tr-sec sec-timeline" id="timeline">
      <.section_head icon="hero-chart-bar" kind="timeline">
        Timeline
        <:actions>
          <span :if={@tl.current} class="tr-count">
            Stage {@tl.current.index + 1} of {length(@tl.spans)}
          </span>
        </:actions>
      </.section_head>

      <p :if={@tl.spans == []} class="tr-muted">
        Add his foaling date with Edit profile to place the program on the calendar.
      </p>

      <%= if @overview do %>
        <div class="tr-label">Whole program</div>
        <svg
          class="tl-svg"
          viewBox={"0 0 #{@w} 58"}
          role="img"
          aria-label={"Program timeline from foaling to #{fmt(elem(@tl.range, 1))}, today marked"}
        >
          <defs>
            <clipPath id="tl-bar-clip">
              <rect x="0" y="20" width={@w} height="16" rx="8" />
            </clipPath>
          </defs>
          <g clip-path="url(#tl-bar-clip)">
            <rect
              :for={s <- @overview.segments}
              x={s.x}
              y="20"
              width={s.w}
              height="16"
              fill={s.color}
              opacity={s.opacity}
            >
              <title>{s.name}: {fmt(s.start)} – {fmt(s.stop)}</title>
            </rect>
          </g>
          <rect
            :if={@overview.current}
            x={@overview.current.x}
            y="18"
            width={@overview.current.w}
            height="20"
            rx="4"
            fill="none"
            class="tl-current"
            stroke-width="2"
          />
          <g :for={g <- @overview.goals}>
            <path d={"M#{g.x} 6 l4 5 l-4 5 l-4 -5 z"} class={["tl-goal", g.done && "done"]}>
              <title>{g.title} · {fmt(g.date)}</title>
            </path>
          </g>
          <line
            :if={@overview.today}
            x1={@overview.today}
            x2={@overview.today}
            y1="14"
            y2="42"
            class="tl-today"
            stroke-width="2.5"
            stroke-linecap="round"
          />
          <g :for={t <- @overview.ticks}>
            <line x1={t.x} x2={t.x} y1="38" y2="42" class="tl-tick" />
            <text x={t.x} y="54" text-anchor={t.anchor} class="tl-axis">{t.label}</text>
          </g>
        </svg>
      <% end %>

      <%= if @zoom do %>
        <div class="tr-label tl-sub">Around today</div>
        <svg
          class="tl-svg"
          viewBox={"0 0 #{@w} 104"}
          role="img"
          aria-label="Stages, logged days and goals from six weeks ago to seven months ahead"
        >
          <rect
            :for={b <- @zoom.bands}
            x={b.x}
            y="22"
            width={b.w}
            height="30"
            rx="6"
            fill={b.color}
            opacity={if b.current, do: "0.32", else: "0.16"}
          />
          <text
            :for={b <- @zoom.bands}
            :if={b.lines != []}
            x={b.x + 7}
            y={if length(b.lines) == 1, do: "41", else: "35"}
            class="tl-band-label"
          >
            <tspan
              :for={{line, i} <- Enum.with_index(b.lines)}
              x={b.x + 7}
              dy={if i == 0, do: "0", else: "13"}
            >{line}</tspan>
          </text>
          <line
            :for={g <- @zoom.goals}
            x1={g.x}
            x2={g.x}
            y1="14"
            y2="72"
            class="tl-goal-line"
          />
          <path
            :for={g <- @zoom.goals}
            d={"M#{g.x} 4 l4 5 l-4 5 l-4 -5 z"}
            class={["tl-goal", g.done && "done"]}
          >
            <title>{g.title} · {fmt(g.date)}</title>
          </path>
          <rect x="0" y="58" width={@w} height="12" rx="3" class="tl-lane" />
          <rect
            :for={d <- @zoom.days}
            x={d.x}
            y="58"
            width="2.6"
            height="12"
            rx="1"
            fill={d.color}
          />
          <g :for={t <- @zoom.ticks}>
            <line x1={t.x} x2={t.x} y1="74" y2="78" class="tl-tick" />
            <text x={t.x + 3} y="90" class="tl-axis">{t.label}</text>
          </g>
          <line
            x1={@zoom.today}
            x2={@zoom.today}
            y1="16"
            y2="78"
            class="tl-today"
            stroke-width="2.5"
            stroke-linecap="round"
          />
          <text x={@zoom.today} y="102" text-anchor="middle" class="tl-today-label">Today</text>
        </svg>
        <div class="tl-legend">
          <span :for={{_cat, label, color} <- Timeline.categories()}>
            <i style={"background:#{color}"}></i>{label}
          </span>
          <span><i class="tl-legend-goal"></i>Goal</span>
        </div>

        <div :if={@upcoming != []} class="tl-up">
          <div :for={g <- @upcoming} class="tl-up-row">
            <span class="tl-up-date">{fmt_short(g.target_date)}</span>
            <span class="tl-up-title">{g.title}</span>
            <span class="tl-up-when">{countdown(Date.diff(g.target_date, @today))}</span>
          </div>
        </div>
      <% end %>

      <div class="tr-stats">
        <div class="tr-stat">
          <b>{@tl.stats.days_in_stage || "–"}</b><span>days in this stage</span>
        </div>
        <div class="tr-stat">
          <b>{@tl.stats.tracked_in_stage || "–"}</b><span>days logged in stage</span>
        </div>
        <div class="tr-stat">
          <b>{@tl.stats.total_days}</b><span>days logged total</span>
        </div>
        <div class="tr-stat">
          <b style={"color:#{Timeline.category_color(:saddled)}"}>{@tl.stats.saddled}</b><span>days saddled</span>
        </div>
        <div class="tr-stat">
          <b style={"color:#{Timeline.category_color(:driving)}"}>{@tl.stats.driving}</b><span>days ground driven</span>
        </div>
        <div class="tr-stat">
          <b style={"color:#{Timeline.category_color(:riding)}"}>{@tl.stats.riding}</b><span>days ridden</span>
        </div>
      </div>
      <p :if={@tl.stats.total_minutes > 0} class="tr-muted tl-hours">
        {hours(@tl.stats.total_minutes)} of logged work in all.
      </p>

      <button
        class="tr-mini tl-toggle"
        phx-click="toggle_weeks"
        aria-expanded={to_string(@show_weeks)}
        aria-controls="tl-weeks"
      >
        {if @show_weeks, do: "Hide weekly activity", else: "Show weekly activity"}
      </button>

      <div :if={@show_weeks} id="tl-weeks" class="tl-sub">
        <div class="tr-label">Days logged per week · last 12 weeks</div>
        <svg
          class="tl-svg"
          viewBox={"0 0 #{@w} 132"}
          role="img"
          aria-label="Days logged per week for the last twelve weeks, by type of work"
        >
          <g :for={y <- [0, 3, 7]}>
            <line x1="22" x2={@w} y1={@chart.y.(y)} y2={@chart.y.(y)} class="tl-grid" />
            <text x="14" y={@chart.y.(y) + 4} text-anchor="end" class="tl-axis">{y}</text>
          </g>
          <g :for={bar <- @chart.bars}>
            <rect
              :for={seg <- bar.segments}
              x={bar.x}
              y={seg.y}
              width={@chart.bar_w}
              height={seg.h}
              fill={seg.color}
            >
              <title>Week of {fmt_short(bar.from)}: {seg.count} {seg.label}</title>
            </rect>
            <text
              :if={bar.label}
              x={bar.x + @chart.bar_w / 2}
              y="128"
              text-anchor="middle"
              class="tl-axis"
            >
              {bar.label}
            </text>
          </g>
        </svg>
        <p :if={@chart.empty} class="tr-muted">Nothing logged in the last 12 weeks yet.</p>
      </div>
    </div>
    """
  end

  # ── Whole-program bar ───────────────────────────────────────────────────────

  defp overview(%{range: nil}, _today), do: nil

  defp overview(%{range: {from, to}} = tl, today) do
    x = scale(from, to, 0, @w)
    current_id = tl.current && tl.current.stage.id

    segments =
      Enum.map(tl.spans, fn s ->
        opacity =
          cond do
            s.stage.id == current_id -> "1"
            Date.compare(s.stop, today) != :gt -> "0.85"
            true -> "0.35"
          end

        %{
          x: x.(s.start),
          w: max(x.(s.stop) - x.(s.start), 0),
          color: s.color,
          opacity: opacity,
          name: s.stage.name,
          start: s.start,
          stop: s.stop
        }
      end)

    current =
      tl.current &&
        %{x: x.(tl.current.start), w: max(x.(tl.current.stop) - x.(tl.current.start), 0)}

    goals =
      for g <- tl.goals, in_range?(g.target_date, from, to) do
        %{x: x.(g.target_date), title: g.title, date: g.target_date, done: g.status == "done"}
      end

    # A tick at each birthday.
    years = div(Date.diff(to, from), 365)

    ticks =
      for n <- 0..years//1,
          date <- [Timeline.add_months(from, 12 * n)],
          Date.compare(date, to) != :gt do
        anchor =
          cond do
            n == 0 -> "start"
            x.(date) > @w - 20 -> "end"
            true -> "middle"
          end

        %{x: x.(date), label: if(n == 0, do: "Foaled", else: "#{n} yr"), anchor: anchor}
      end

    %{
      segments: segments,
      current: current,
      goals: goals,
      ticks: ticks,
      today: if(in_range?(today, from, to), do: x.(today))
    }
  end

  # ── Around today ────────────────────────────────────────────────────────────

  defp zoom(%{window: {from, to}} = tl, today) do
    x = scale(from, to, 0, @w)
    current_id = tl.current && tl.current.stage.id

    bands =
      for s <- tl.spans,
          Date.compare(s.stop, from) == :gt and Date.compare(s.start, to) == :lt do
        x1 = x.(latest(s.start, from))
        x2 = x.(earliest(s.stop, to))
        w = Float.round(max(x2 - x1 - 2, 0.0), 1)

        %{
          x: x1 + 1,
          w: w,
          color: s.color,
          current: s.stage.id == current_id,
          lines: fit_lines(s.stage.name, w - 12)
        }
      end

    days =
      for d <- tl.days, in_range?(d.date, from, to) do
        %{x: x.(d.date) - 1.3, color: Timeline.category_color(d.category)}
      end

    goals =
      for g <- tl.goals, in_range?(g.target_date, from, to) do
        %{x: x.(g.target_date), title: g.title, date: g.target_date, done: g.status == "done"}
      end

    %{bands: bands, days: days, goals: goals, ticks: month_ticks(from, to, x), today: x.(today)}
  end

  defp month_ticks(from, to, x) do
    first = Date.new!(from.year, from.month, 1)

    0..12
    |> Enum.map(&Timeline.add_months(first, &1))
    |> Enum.filter(&(Date.compare(&1, from) == :gt and Date.compare(&1, to) == :lt))
    |> Enum.map(fn date ->
      %{x: x.(date), label: Calendar.strftime(date, "%b")}
    end)
    # Keep the last label from running off the edge.
    |> Enum.filter(&(&1.x < @w - 22))
  end

  defp upcoming(%{window: {_from, to}, goals: goals}, today) do
    goals
    |> Enum.filter(
      &(&1.status == "active" and Date.compare(&1.target_date, today) != :lt and
          Date.compare(&1.target_date, to) != :gt)
    )
    |> Enum.take(4)
  end

  # ── Weekly chart ────────────────────────────────────────────────────────────

  @chart_top 8
  @chart_bottom 112
  @max_days 7

  defp week_chart(%{weeks: weeks}) do
    left = 26
    slot = (@w - left) / length(weeks)
    bar_w = Float.round(slot * 0.62, 1)

    y = fn days ->
      Float.round(@chart_bottom - days / @max_days * (@chart_bottom - @chart_top), 1)
    end

    bars =
      weeks
      |> Enum.with_index()
      |> Enum.map(fn {wk, i} ->
        {segments, _} =
          Enum.map_reduce(Timeline.categories(), 0, fn {cat, label, color}, below ->
            count = Map.get(wk.counts, cat, 0)
            top = below + count

            seg = %{
              y: y.(min(top, @max_days)),
              h: Float.round(y.(min(below, @max_days)) - y.(min(top, @max_days)), 1),
              color: color,
              count: count,
              label: String.downcase(label)
            }

            {seg, top}
          end)

        %{
          x: Float.round(left + i * slot + (slot - bar_w) / 2, 1),
          from: wk.from,
          segments: Enum.filter(segments, &(&1.count > 0)),
          label: if(rem(length(weeks) - 1 - i, 3) == 0, do: fmt_short(wk.from))
        }
      end)

    %{bars: bars, bar_w: bar_w, y: y, empty: Enum.all?(weeks, &(&1.total == 0))}
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  # A function mapping a date onto [x0, x1] for the span from..to.
  defp scale(from, to, x0, x1) do
    span = max(Date.diff(to, from), 1)
    fn date -> Float.round(x0 + Date.diff(date, from) / span * (x1 - x0), 1) end
  end

  defp in_range?(date, from, to),
    do: Date.compare(date, from) != :lt and Date.compare(date, to) != :gt

  defp latest(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
  defp earliest(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)

  # A stage name in at most two lines that fit `room` px (about 6.2px a character
  # at 11px), ending in "…" if it had to be cut. No label when not even a word fits.
  @char_px 6.2

  defp fit_lines(name, room) do
    max_chars = trunc(room / @char_px)
    words = String.split(name)

    {line1, rest} = take_words(words, max_chars)
    {line2, rest} = take_words(rest, max_chars)

    lines =
      cond do
        line1 == "" -> []
        rest == [] -> Enum.reject([line1, line2], &(&1 == ""))
        line2 == "" -> [ellipsize(line1, max_chars)]
        true -> [line1, ellipsize(line2, max_chars)]
      end

    if lines != [] and String.length(hd(lines)) >= 3, do: lines, else: []
  end

  defp take_words(words, max_chars), do: take_words(words, max_chars, "")

  defp take_words([w | rest] = words, max_chars, acc) do
    next = if acc == "", do: w, else: acc <> " " <> w
    if String.length(next) <= max_chars, do: take_words(rest, max_chars, next), else: {acc, words}
  end

  defp take_words([], _max_chars, acc), do: {acc, []}

  defp ellipsize(line, max_chars) do
    if String.length(line) + 1 <= max_chars,
      do: line <> "…",
      else: String.slice(line, 0, max(max_chars - 1, 0)) <> "…"
  end

  defp fmt(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
  defp fmt_short(%Date{} = d), do: Calendar.strftime(d, "%b %-d")

  defp hours(minutes) when minutes < 60, do: "#{minutes} minutes"

  defp hours(minutes) do
    h = Float.round(minutes / 60, 1)
    h = if h == trunc(h), do: trunc(h), else: h
    "#{h} #{if h == 1, do: "hour", else: "hours"}"
  end
end
