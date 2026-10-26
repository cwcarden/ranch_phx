defmodule RanchPhxWeb.TrainingTimeline do
  @moduledoc """
  The Timeline card on a training book: the whole program as a colored bar, a
  closer look at the months around today with logged days and goals, day counts,
  and an optional weekly activity chart. Drawn as inline SVG, no chart library.
  """
  use Phoenix.Component
  import RanchPhxWeb.TrainingComponents, only: [section_head: 1]
  alias RanchPhx.Training.Timeline

  # SVG coordinate width; everything scales to the card width.
  @w 340

  attr :tl, :map, required: true
  attr :today, Date, required: true
  attr :show_weeks, :boolean, default: false
  attr :selected_id, :integer, default: nil, doc: "stage opened by tapping it, if any"

  def timeline_card(assigns) do
    %{tl: tl, today: today} = assigns
    sel = assigns.selected_id && Enum.find(tl.spans, &(&1.stage.id == assigns.selected_id))

    assigns =
      assigns
      |> assign(:sel, sel)
      |> assign(:sel_info, sel && stage_info(sel, tl, today))
      |> assign(:overview, overview(tl, today, sel))
      |> assign(:zoom, zoom(tl, today, sel))
      |> assign(:chart, week_chart(tl))
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
        <svg
          class="tl-svg"
          viewBox={"0 0 #{@w} 58"}
          role="img"
          aria-label={"Program timeline from foaling to #{fmt(elem(@tl.range, 1))}, today marked. Tap a stage to open it."}
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
            />
          </g>
          <rect
            :if={@overview.outline}
            x={@overview.outline.x}
            y="18"
            width={@overview.outline.w}
            height="20"
            rx="4"
            fill="none"
            class="tl-current"
            stroke-width="2"
          />
          <path
            :for={g <- @overview.goals}
            d={"M#{g.x} 6 l4 5 l-4 5 l-4 -5 z"}
            class={["tl-goal", g.done && "done"]}
          />
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
          <%!-- Tall invisible targets on top so short stages are still easy to tap --%>
          <rect
            :for={s <- @overview.segments}
            x={s.x}
            y="2"
            width={s.w}
            height="42"
            class="tl-hit"
            phx-click="tl_stage"
            phx-value-id={s.id}
          >
            <title>{s.name}: {fmt(s.start)} – {fmt(s.stop)}</title>
          </rect>
        </svg>
      <% end %>

      <div :if={@sel} id="tl-stage" class="tl-detail" style={"--stage: #{@sel.color}"}>
        <div class="tl-detail-head">
          <button
            class="tl-nav"
            phx-click="tl_stage"
            phx-value-id={@sel_info.prev && @sel_info.prev.stage.id}
            disabled={is_nil(@sel_info.prev)}
            aria-label="Previous stage"
          >
            ‹
          </button>
          <div class="tl-detail-title">
            <span class="tl-status"><i></i>{@sel_info.status} · Stage {@sel.index + 1}</span>
            <b>{@sel.stage.name}</b>
          </div>
          <button
            class="tl-nav"
            phx-click="tl_stage"
            phx-value-id={@sel_info.next && @sel_info.next.stage.id}
            disabled={is_nil(@sel_info.next)}
            aria-label="Next stage"
          >
            ›
          </button>
          <button class="tl-nav" phx-click="tl_close" aria-label="Close stage">×</button>
        </div>
        <p class="tl-meta">
          {fmt_short(@sel.start)} – {fmt(@sel.stop)} · {@sel_info.ages}<span :if={@sel.logged > 0}> · {@sel.logged} {if @sel.logged == 1, do: "day", else: "days"} logged</span>
        </p>
        <p :if={@sel.stage.summary} class="tr-muted" style="margin-top:6px">{@sel.stage.summary}</p>
        <ul :if={@sel.stage.focus != []} class="tr-list">
          <li :for={f <- @sel.stage.focus}>{f}</li>
        </ul>
        <div :if={@sel.stage.guardrail} class="tr-guard">
          <b>Keep it light:</b> {@sel.stage.guardrail}
          <span :if={@sel.stage.max_session_minutes}>
            Up to {@sel.stage.max_session_minutes} min a session<span :if={
              @sel.stage.max_sessions_per_week
            }>, {@sel.stage.max_sessions_per_week} sessions a week</span>.
          </span>
        </div>
      </div>

      <%= if @zoom.bands != [] or @zoom.days != [] do %>
        <div class="tr-label tl-sub">Around today</div>
        <svg
          class="tl-svg"
          viewBox={"0 0 #{@w} 104"}
          role="img"
          aria-label="Stages, logged days and goals from six weeks ago to seven months ahead. Tap a stage to open it."
        >
          <rect
            :for={b <- @zoom.bands}
            x={b.x}
            y="22"
            width={b.w}
            height="30"
            rx="6"
            fill={b.color}
            opacity={if b.strong, do: "0.34", else: "0.16"}
            class="tl-hit-band"
            phx-click="tl_stage"
            phx-value-id={b.id}
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
      <% end %>

      <div class="tr-stats tl-stats">
        <div class="tr-stat">
          <b>{@tl.stats.days_in_stage || "–"}</b><span>in stage</span>
        </div>
        <div class="tr-stat">
          <b style={"color:#{Timeline.category_color(:saddled)}"}>{@tl.stats.saddled}</b><span>saddled</span>
        </div>
        <div class="tr-stat">
          <b style={"color:#{Timeline.category_color(:driving)}"}>{@tl.stats.driving}</b><span>driven</span>
        </div>
        <div class="tr-stat">
          <b style={"color:#{Timeline.category_color(:riding)}"}>{@tl.stats.riding}</b><span>ridden</span>
        </div>
      </div>

      <button
        class="tr-mini tl-toggle"
        phx-click="toggle_weeks"
        aria-expanded={to_string(@show_weeks)}
        aria-controls="tl-weeks"
      >
        {if @show_weeks, do: "Hide weekly activity", else: "Weekly activity"}
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

  # ── The opened stage ────────────────────────────────────────────────────────

  defp stage_info(sel, tl, today) do
    next = Enum.at(tl.spans, sel.index + 1)
    prev = if sel.index > 0, do: Enum.at(tl.spans, sel.index - 1)
    from = sel.stage.from_age_months
    to = if next, do: next.stage.from_age_months, else: from + 6

    status =
      cond do
        tl.current && sel.stage.id == tl.current.stage.id -> "Now"
        Date.compare(sel.stop, today) != :gt -> "Done"
        tl.current && sel.index == tl.current.index + 1 -> "Up next"
        true -> "Later"
      end

    %{status: status, prev: prev, next: next, ages: age_range(from, to)}
  end

  defp age_range(from, to) when to <= 24, do: "#{from}–#{to} months"
  defp age_range(from, to), do: "#{age_words(from)} – #{age_words(to)}"

  defp age_words(m) when m < 24, do: "#{m} months"
  defp age_words(m) when rem(m, 12) == 0, do: "#{div(m, 12)} years"
  defp age_words(m), do: "#{div(m, 12)} yrs #{rem(m, 12)} mo"

  # ── Whole-program bar ───────────────────────────────────────────────────────

  defp overview(%{range: nil}, _today, _sel), do: nil

  defp overview(%{range: {from, to}} = tl, today, sel) do
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
          id: s.stage.id,
          x: x.(s.start),
          w: max(x.(s.stop) - x.(s.start), 0),
          color: s.color,
          opacity: opacity,
          name: s.stage.name,
          start: s.start,
          stop: s.stop
        }
      end)

    # Outline the opened stage, or the current one when none is open.
    marked = sel || tl.current
    outline = marked && %{x: x.(marked.start), w: max(x.(marked.stop) - x.(marked.start), 0)}

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
      outline: outline,
      goals: goals,
      ticks: ticks,
      today: if(in_range?(today, from, to), do: x.(today))
    }
  end

  # ── Around today ────────────────────────────────────────────────────────────

  defp zoom(%{window: {from, to}} = tl, today, sel) do
    x = scale(from, to, 0, @w)
    strong_id = (sel || tl.current) && (sel || tl.current).stage.id

    bands =
      for s <- tl.spans,
          Date.compare(s.stop, from) == :gt and Date.compare(s.start, to) == :lt do
        x1 = x.(latest(s.start, from))
        x2 = x.(earliest(s.stop, to))
        w = Float.round(max(x2 - x1 - 2, 0.0), 1)

        %{
          id: s.stage.id,
          x: x1 + 1,
          w: w,
          color: s.color,
          strong: s.stage.id == strong_id,
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
end
