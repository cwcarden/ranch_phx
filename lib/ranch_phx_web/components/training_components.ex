defmodule RanchPhxWeb.TrainingComponents do
  @moduledoc """
  Shared look for the training pages: mobile-first, big tap targets,
  readable at arm's length. Uses the same color tokens as the rest of the app.
  """
  use Phoenix.Component

  attr :back, :string, default: nil
  attr :back_label, :string, default: nil
  attr :title, :string, required: true

  def topbar(assigns) do
    ~H"""
    <div class="tr-topbar">
      <a :if={@back} class="tr-back" href={@back}>
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          width="18"
          height="18"
        >
          <polyline points="15 18 9 12 15 6" />
        </svg>
        {@back_label}
      </a>
      <span class="tr-title">{@title}</span>
    </div>
    """
  end

  attr :horse, :map, required: true
  attr :size, :integer, default: 64

  def horse_photo(assigns) do
    ~H"""
    <div class="tr-photo" style={"width:#{@size}px;height:#{@size}px"}>
      <img :if={@horse.photo_url} src={@horse.photo_url} alt={@horse.name} />
      <span :if={is_nil(@horse.photo_url)}>{String.first(@horse.name || "?")}</span>
    </div>
    """
  end

  @doc "Big take-or-choose-photo button with a preview. On iPhone it offers the camera or library."
  attr :upload, :any, required: true
  attr :label, :string, default: "Take or choose a photo"
  attr :cancel_event, :string, default: "cancel_photo"

  def photo_picker(assigns) do
    ~H"""
    <div class="tr-picker">
      <label class="tr-btn" style="width:100%">
        <.live_file_input upload={@upload} class="tr-file" />
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          width="18"
          height="18"
        >
          <path d="M23 19a2 2 0 01-2 2H3a2 2 0 01-2-2V8a2 2 0 012-2h4l2-3h6l2 3h4a2 2 0 012 2z" />
          <circle cx="12" cy="13" r="4" />
        </svg>
        {@label}
      </label>
      <div :for={entry <- @upload.entries} class="tr-preview" id={"preview-#{entry.ref}"}>
        <.live_img_preview entry={entry} />
        <div style="flex:1">
          <div :if={entry.progress > 0 and entry.progress < 100} class="tr-muted">
            Uploading {entry.progress}%
          </div>
          <div :for={err <- upload_errors(@upload, entry)} class="tr-error">{upload_error(err)}</div>
        </div>
        <button
          type="button"
          class="tr-link-btn"
          phx-click={@cancel_event}
          phx-value-ref={entry.ref}
        >
          Remove
        </button>
      </div>
      <div :for={err <- upload_errors(@upload)} class="tr-error">{upload_error(err)}</div>
    </div>
    """
  end

  defp upload_error(:too_large), do: "That photo is too big (20 MB max)."
  defp upload_error(:not_accepted), do: "That file type isn't a photo."
  defp upload_error(:too_many_files), do: "Just one photo."
  defp upload_error(err), do: "Upload problem: #{err}"

  @doc "Add/edit form for one goal."
  attr :form, :any, required: true
  attr :new, :boolean, default: false
  attr :goal_id, :any, default: nil

  def goal_form(assigns) do
    ~H"""
    <.form
      for={@form}
      as={:goal}
      id={"goal-form-#{@goal_id || "new"}"}
      phx-submit="save_goal"
      style="margin:8px 0 4px"
    >
      <div class="tr-field">
        <label for={"goal_title_#{@goal_id}"}>Goal</label>
        <input
          type="text"
          id={"goal_title_#{@goal_id}"}
          name="goal[title]"
          value={@form[:title].value}
          placeholder="e.g. Stands tied quietly for 20 minutes"
          required
        />
        <span :for={{msg, _} <- @form[:title].errors} class="tr-error">{msg}</span>
      </div>
      <div class="tr-field">
        <label for={"goal_date_#{@goal_id}"}>Target date (optional)</label>
        <input
          type="date"
          id={"goal_date_#{@goal_id}"}
          name="goal[target_date]"
          value={@form[:target_date].value}
        />
      </div>
      <div class="tr-field">
        <label for={"goal_notes_#{@goal_id}"}>Notes (optional)</label>
        <textarea
          id={"goal_notes_#{@goal_id}"}
          name="goal[notes]"
          placeholder="What done looks like, how you'll get there…"
        >{@form[:notes].value}</textarea>
      </div>
      <div class="tr-row" style="justify-content:flex-start">
        <button type="submit" class="tr-btn tr-btn-primary tr-btn-small">
          {if @new, do: "Add goal", else: "Save"}
        </button>
        <button type="button" class="tr-btn tr-btn-small" phx-click="cancel_goal">Cancel</button>
        <button
          :if={@goal_id}
          type="button"
          class="tr-link-btn"
          phx-click="goal_status"
          phx-value-id={@goal_id}
          phx-value-status="dropped"
        >
          Drop goal
        </button>
        <button
          :if={@goal_id}
          type="button"
          class="tr-link-btn"
          phx-click="delete_goal"
          phx-value-id={@goal_id}
          data-confirm="Delete this goal for good?"
        >
          Delete
        </button>
      </div>
    </.form>
    """
  end

  @doc "Add/edit form for one Working on item."
  attr :form, :any, required: true
  attr :activities, :list, required: true
  attr :issue_id, :any, default: nil

  def issue_form(assigns) do
    ~H"""
    <.form
      for={@form}
      as={:issue}
      id={"issue-form-#{@issue_id || "new"}"}
      phx-submit="save_issue"
      style="margin:8px 0 4px"
    >
      <div class="tr-field">
        <label for={"issue_title_#{@issue_id}"}>What are you working on?</label>
        <input
          type="text"
          id={"issue_title_#{@issue_id}"}
          name="issue[title]"
          value={@form[:title].value}
          placeholder="e.g. Picking up left hind"
          required
        />
        <span :for={{msg, _} <- @form[:title].errors} class="tr-error">{msg}</span>
      </div>
      <div class="tr-two">
        <div class="tr-field">
          <label for={"issue_activity_#{@issue_id}"}>Activity</label>
          <select id={"issue_activity_#{@issue_id}"} name="issue[activity_id]">
            <option value="">–</option>
            <option
              :for={a <- Enum.reject(@activities, & &1.archived)}
              value={a.id}
              selected={"#{a.id}" == "#{@form[:activity_id].value}"}
            >
              {a.name}
            </option>
          </select>
        </div>
        <div class="tr-field">
          <label for={"issue_side_#{@issue_id}"}>Side</label>
          <select id={"issue_side_#{@issue_id}"} name="issue[side]">
            <option value="">–</option>
            <option
              :for={{v, l} <- [{"left", "Left"}, {"right", "Right"}, {"both", "Both"}]}
              value={v}
              selected={@form[:side].value == v}
            >
              {l}
            </option>
          </select>
        </div>
      </div>
      <div class="tr-field">
        <label for={"issue_notes_#{@issue_id}"}>Notes (optional)</label>
        <textarea
          id={"issue_notes_#{@issue_id}"}
          name="issue[notes]"
          placeholder="What it looks like, what you've tried…"
        >{@form[:notes].value}</textarea>
      </div>
      <div class="tr-row" style="justify-content:flex-start">
        <button type="submit" class="tr-btn tr-btn-primary tr-btn-small">
          {if @issue_id, do: "Save", else: "Add"}
        </button>
        <button type="button" class="tr-btn tr-btn-small" phx-click="cancel_issue">Cancel</button>
        <button
          :if={@issue_id}
          type="button"
          class="tr-link-btn"
          phx-click="delete_issue"
          phx-value-id={@issue_id}
          data-confirm="Delete this and its history from every session?"
        >
          Delete
        </button>
      </div>
    </.form>
    """
  end

  @doc "Short countdown to a date: \"in 16 months\", \"in 12 days\", \"Tomorrow\", \"3 days past\"."
  def countdown(nil), do: nil

  def countdown(days) when is_integer(days) do
    cond do
      days > 90 -> "in #{div(days, 30)} months"
      days > 1 -> "in #{days} days"
      days == 1 -> "Tomorrow"
      days == 0 -> "Today"
      days == -1 -> "1 day past"
      true -> "#{-days} days past"
    end
  end

  @doc """
  Header for a section of the book: a colored icon badge, the title, and actions on the
  right. `kind` picks the section's color (goals, working, stage, trainer, log, sessions).
  """
  attr :icon, :string, required: true
  attr :kind, :string, required: true
  slot :inner_block, required: true
  slot :actions

  def section_head(assigns) do
    ~H"""
    <div class="tr-sec-head">
      <span class={["tr-sec-ico", "sec-#{@kind}"]} aria-hidden="true">
        <RanchPhxWeb.CoreComponents.icon name={@icon} />
      </span>
      <h2>{render_slot(@inner_block)}</h2>
      <div :if={@actions != []} class="tr-sec-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc "Sticky row of section shortcuts under the top bar: `{anchor, label, icon, kind}`."
  attr :items, :list, required: true

  def section_nav(assigns) do
    ~H"""
    <nav class="tr-jump" aria-label="Sections">
      <a :for={{anchor, label, icon, kind} <- @items} href={"##{anchor}"} class={"sec-#{kind}"}>
        <RanchPhxWeb.CoreComponents.icon name={icon} />
        {label}
      </a>
    </nav>
    """
  end

  @doc """
  A TrAIner answer as readable text: paragraphs, bulleted and numbered lists, and
  **bold**, instead of raw text with dashes. Everything is escaped as plain text.
  """
  attr :text, :string, required: true

  def coach_answer(assigns) do
    assigns = assign(assigns, :blocks, answer_blocks(assigns.text))

    ~H"""
    <div class="tr-prose">
      <%= for block <- @blocks do %>
        <%= case block do %>
          <% {:ul, items} -> %>
            <ul>
              <li :for={item <- items}><.inline parts={item} /></li>
            </ul>
          <% {:ol, items} -> %>
            <ol>
              <li :for={item <- items}><.inline parts={item} /></li>
            </ol>
          <% {:h, parts} -> %>
            <p class="tr-prose-h"><.inline parts={parts} /></p>
          <% {:p, lines} -> %>
            <p>
              <%= for {line, i} <- Enum.with_index(lines) do %>
                <br :if={i > 0} /><.inline parts={line} />
              <% end %>
            </p>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :parts, :list, required: true

  defp inline(assigns) do
    ~H"""
    <%= for part <- @parts do %>
      <%= case part do %>
        <% {:b, t} -> %>
          <strong>{t}</strong>
        <% {:t, t} -> %>
          {t}
      <% end %>
    <% end %>
    """
  end

  @bullet ~r/^\s*(?:[-*•])\s+(.*)$/
  @numbered ~r/^\s*\d+[.)]\s+(.*)$/
  @heading ~r/^\s*#+\s+(.*)$/

  @doc false
  def answer_blocks(text) do
    (text || "")
    |> String.replace("\r\n", "\n")
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.flat_map(fn para ->
      para
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.chunk_by(&line_kind/1)
      |> Enum.map(&to_block/1)
    end)
  end

  defp line_kind(line) do
    cond do
      Regex.match?(@bullet, line) -> :ul
      Regex.match?(@numbered, line) -> :ol
      Regex.match?(@heading, line) -> :h
      true -> :p
    end
  end

  defp to_block([first | _] = lines) do
    case line_kind(first) do
      :ul ->
        {:ul, Enum.map(lines, &(@bullet |> Regex.run(&1) |> List.last() |> parse_inline()))}

      :ol ->
        {:ol, Enum.map(lines, &(@numbered |> Regex.run(&1) |> List.last() |> parse_inline()))}

      :h ->
        {:h,
         lines
         |> Enum.map_join(" ", &(@heading |> Regex.run(&1) |> List.last()))
         |> parse_inline()}

      :p ->
        {:p, Enum.map(lines, &(&1 |> String.trim() |> parse_inline()))}
    end
  end

  # "**bold**" becomes {:b, "bold"}; everything else stays plain text.
  defp parse_inline(text) do
    ~r/\*\*(.+?)\*\*/
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(fn
      "**" <> rest = s ->
        if String.ends_with?(s, "**"), do: {:b, String.trim_trailing(rest, "**")}, else: {:t, s}

      s ->
        {:t, s}
    end)
  end

  def styles(assigns) do
    ~H"""
    <style>
      :root {
        --brand: #8b5cf6; --brand-soft: #ede9fe;
        --surface: #ffffff; --surface2: #f9fafb; --border: #e5e7eb;
        --text: #111827; --text2: #4b5563; --text3: #9ca3af;
        --warn: #b45309; --warn-soft: #fef3c7;
        --radius: 14px;
      }
      [data-theme="dark"] {
        --brand: #a78bfa; --brand-soft: #2e1065;
        --surface: #1e1e2e; --surface2: #16161e; --border: #2d2d3d;
        --text: #e2e8f0; --text2: #cbd5e1; --text3: #64748b;
        --warn: #fbbf24; --warn-soft: #422006;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--surface2); color: var(--text); font-size: 17px; line-height: 1.45; }

      .tr-topbar { position: sticky; top: calc(52px + env(safe-area-inset-top)); z-index: 50; height: 56px; display: flex; align-items: center; gap: 12px; padding: 0 16px; background: var(--surface); border-bottom: 1px solid var(--border); }
      .tr-back { display: inline-flex; align-items: center; gap: 4px; min-height: 44px; color: var(--brand); font-weight: 600; text-decoration: none; font-size: 16px; }
      .tr-title { font-weight: 700; font-size: 18px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

      .tr-wrap { max-width: 720px; margin: 0 auto; padding: 16px 16px 48px; display: grid; gap: 16px; }
      /* Grid items default to their content's min width; long one-line text would widen the page. */
      .tr-wrap > * { min-width: 0; }
      .tr-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 18px; }
      .tr-card h2 { font-size: 20px; font-weight: 700; line-height: 1.25; }
      .tr-label { font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; color: var(--text3); margin-bottom: 6px; }
      .tr-muted { color: var(--text2); font-size: 15px; }
      .tr-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
      html { background: var(--surface2); }
      .tr-list { list-style: disc; padding-left: 20px; display: grid; gap: 4px; margin-top: 8px; }
      .tr-guard { margin-top: 12px; padding: 12px 14px; border-radius: 10px; background: var(--brand-soft); font-size: 15px; }
      .tr-warn { padding: 12px 14px; border-radius: 10px; background: var(--warn-soft); color: var(--warn); font-size: 15px; font-weight: 600; }
      .tr-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-top: 14px; }
      .tr-stat { background: var(--surface2); border-radius: 10px; padding: 10px; text-align: center; }
      .tr-stat b { display: block; font-size: 22px; }
      .tr-stat span { font-size: 13px; color: var(--text2); }

      .tr-btn { display: inline-flex; align-items: center; justify-content: center; gap: 6px; min-height: 48px; padding: 0 20px; border-radius: 12px; border: 1.5px solid var(--border); background: var(--surface); color: var(--text); font-size: 16px; font-weight: 600; cursor: pointer; text-decoration: none; }
      .tr-btn-primary { background: var(--brand); border-color: var(--brand); color: #fff; }
      .tr-btn-block { width: 100%; min-height: 56px; font-size: 18px; }
      .tr-btn-small { min-height: 40px; padding: 0 14px; font-size: 14px; }

      .tr-field { display: grid; gap: 6px; margin-bottom: 16px; }
      .tr-field > label, .tr-field > .tr-label { font-size: 14px; font-weight: 700; color: var(--text2); text-transform: none; letter-spacing: 0; margin: 0; }
      .tr-field input[type=date], .tr-field input[type=number], .tr-field input[type=text], .tr-field select, .tr-field textarea { width: 100%; min-height: 48px; padding: 10px 12px; border: 1.5px solid var(--border); border-radius: 10px; background: var(--surface2); color: var(--text); font-size: 17px; }
      .tr-field textarea { min-height: 96px; resize: vertical; }
      .tr-field input:focus, .tr-field select:focus, .tr-field textarea:focus { outline: none; border-color: var(--brand); }
      .tr-error { color: #dc2626; font-size: 14px; }

      .tr-pills { display: flex; flex-wrap: wrap; gap: 8px; }
      .tr-pill { position: relative; }
      .tr-pill input { position: absolute; opacity: 0; pointer-events: none; }
      .tr-pill span { display: inline-flex; align-items: center; min-height: 44px; padding: 0 16px; border-radius: 22px; border: 1.5px solid var(--border); background: var(--surface); font-size: 16px; font-weight: 600; cursor: pointer; user-select: none; }
      .tr-pill input:checked + span { background: var(--brand); border-color: var(--brand); color: #fff; }
      .tr-pill input:focus-visible + span { outline: 2px solid var(--brand); outline-offset: 2px; }
      .tr-pill.dim span { opacity: .45; }

      .tr-horse { display: block; text-decoration: none; color: inherit; }
      .tr-horse:active { opacity: .8; }
      .tr-session { padding: 14px 0; border-top: 1px solid var(--border); }
      .tr-session:first-child { border-top: none; padding-top: 0; }
      .tr-tag { display: inline-block; padding: 2px 10px; border-radius: 12px; background: var(--surface2); border: 1px solid var(--border); font-size: 13px; margin: 4px 4px 0 0; }
      .tr-tag.sore { background: var(--warn-soft); color: var(--warn); border-color: transparent; }
      .tr-link-btn { background: none; border: none; color: var(--text3); font-size: 14px; cursor: pointer; min-height: 40px; padding: 0 8px; }

      .tr-horse-head { display: flex; gap: 14px; align-items: center; }
      .tr-photo { flex: none; border-radius: 12px; overflow: hidden; background: var(--brand-soft); color: var(--brand); display: flex; align-items: center; justify-content: center; font-size: 26px; font-weight: 700; }
      .tr-photo img { width: 100%; height: 100%; object-fit: cover; }
      .tr-segment { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; padding: 4px; border-radius: 12px; background: var(--surface2); border: 1px solid var(--border); }
      .tr-segment button { min-height: 44px; border: none; border-radius: 9px; background: none; font-size: 16px; font-weight: 600; color: var(--text2); cursor: pointer; }
      .tr-segment button.on { background: var(--surface); color: var(--brand); box-shadow: 0 1px 3px rgba(0,0,0,.12); }
      .tr-two { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
      .tr-file { position: absolute; width: 1px; height: 1px; opacity: 0; overflow: hidden; }
      .tr-picker .tr-btn { position: relative; }
      .tr-preview { display: flex; align-items: center; gap: 12px; margin-top: 10px; }
      .tr-preview img { width: 72px; height: 72px; object-fit: cover; border-radius: 10px; }

      .tr-quick { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 16px; }
      .tr-routine { display: inline-flex; align-items: center; }
      .tr-detail { margin: -6px 0 16px; padding: 12px; border-radius: 12px; background: var(--surface2); border: 1px solid var(--border); display: grid; gap: 8px; }
      .tr-pills-sm .tr-pill span { min-height: 40px; padding: 0 14px; font-size: 15px; }
      .tr-pill.res-good input:checked + span { background: #16a34a; border-color: #16a34a; }
      .tr-pill.res-mixed input:checked + span { background: #d97706; border-color: #d97706; }
      .tr-pill.res-trouble input:checked + span { background: #dc2626; border-color: #dc2626; }
      .tr-pill.tag-health input:checked + span { background: var(--warn); border-color: var(--warn); }
      .tr-detail-note { width: 100%; min-height: 44px; padding: 8px 12px; border: 1.5px solid var(--border); border-radius: 10px; background: var(--surface); color: var(--text); font-size: 16px; }
      .tr-res { font-weight: 700; }
      .tr-chip { min-height: 40px; padding: 0 14px; border-radius: 20px; border: 1.5px solid var(--border); background: var(--surface); color: var(--text); font-size: 15px; cursor: pointer; text-align: left; }
      .tr-chip:disabled { opacity: .5; }
      .tr-earlier { display: block; width: 100%; max-width: 100%; text-align: left; padding: 8px 0; color: var(--text2); font-size: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; border-top: 1px solid var(--border); border-radius: 0; }
      .tr-answer { margin-top: 14px; padding: 14px; border-radius: 12px; background: var(--surface2); border: 1px solid var(--border); }
      .tr-status { font-size: 13px; font-weight: 700; padding: 2px 10px; border-radius: 12px; background: var(--surface2); border: 1px solid var(--border); }
      .tr-status.st-open { color: #dc2626; }
      .tr-status.st-improving { color: #d97706; }
      .tr-status.st-solved { color: #16a34a; }
      .tr-trend { display: flex; gap: 4px; margin-top: 6px; }
      .tr-mark { width: 26px; height: 26px; border-radius: 7px; display: inline-flex; align-items: center; justify-content: center; font-weight: 700; color: #fff; font-size: 15px; }
      .tr-mark.mk-better { background: #16a34a; }
      .tr-mark.mk-same { background: #9ca3af; }
      .tr-mark.mk-worse { background: #dc2626; }
      .tr-res.mk-better { color: #16a34a; }
      .tr-res.mk-same { color: var(--text2); }
      .tr-res.mk-worse { color: #dc2626; }
      .tr-pill.mk-better input:checked + span { background: #16a34a; border-color: #16a34a; }
      .tr-pill.mk-same input:checked + span { background: #6b7280; border-color: #6b7280; }
      .tr-pill.mk-worse input:checked + span { background: #dc2626; border-color: #dc2626; }
      .tr-history { margin-top: 8px; padding: 10px 12px; border-radius: 10px; background: var(--surface2); display: grid; gap: 4px; }
      .tr-thumbs { display: grid; grid-template-columns: repeat(auto-fill, minmax(84px, 1fr)); gap: 6px; margin-top: 8px; }
      .tr-thumb { position: relative; aspect-ratio: 1; border-radius: 10px; overflow: hidden; background: var(--surface2); border: none; padding: 0; cursor: pointer; }
      .tr-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
      .tr-thumb-x { position: absolute; top: 4px; right: 4px; width: 32px; height: 32px; border-radius: 50%; border: none; background: rgba(0,0,0,.6); color: #fff; font-size: 16px; cursor: pointer; }
      .tr-lightbox { position: fixed; inset: 0; z-index: 200; background: rgba(0,0,0,.92); display: flex; align-items: center; justify-content: center; padding: 16px; }
      .tr-lightbox img { max-width: 100%; max-height: 100%; object-fit: contain; border-radius: 8px; }
      .tr-lightbox-close { position: fixed; top: max(12px, env(safe-area-inset-top)); right: 12px; width: 48px; height: 48px; border-radius: 50%; border: none; background: rgba(255,255,255,.2); color: #fff; font-size: 22px; cursor: pointer; }
      .tr-list-row { display: flex; align-items: center; gap: 4px; min-height: 52px; border-top: 1px solid var(--border); flex-wrap: wrap; }
      .tr-icon-btn { width: 40px; height: 40px; border-radius: 10px; border: 1.5px solid var(--border); background: var(--surface); color: var(--text2); font-size: 18px; cursor: pointer; }
      .tr-icon-btn:disabled { opacity: .3; cursor: default; }
      .tr-res.res-good { color: #16a34a; }
      .tr-res.res-mixed { color: #d97706; }
      .tr-res.res-trouble { color: #dc2626; }

      /* ── Sections: each one has its own color and icon so it's easy to spot ── */
      .sec-goals    { --sec: #d97706; --sec-soft: #fef3c7; }
      .sec-working  { --sec: #e11d48; --sec-soft: #ffe4e6; }
      .sec-stage    { --sec: #7c3aed; --sec-soft: #ede9fe; }
      .sec-trainer  { --sec: #dc2626; --sec-soft: #fee2e2; }
      .sec-log      { --sec: #16a34a; --sec-soft: #dcfce7; }
      .sec-sessions { --sec: #2563eb; --sec-soft: #dbeafe; }
      .sec-today    { --sec: #0d9488; --sec-soft: #ccfbf1; }
      [data-theme="dark"] .sec-today { --sec: #2dd4bf; --sec-soft: #042f2e; }
      [data-theme="dark"] .sec-goals    { --sec: #fbbf24; --sec-soft: #3a2705; }
      [data-theme="dark"] .sec-working  { --sec: #fb7185; --sec-soft: #3f0d1a; }
      [data-theme="dark"] .sec-stage    { --sec: #a78bfa; --sec-soft: #2e1065; }
      [data-theme="dark"] .sec-trainer  { --sec: #f87171; --sec-soft: #3b0d0d; }
      [data-theme="dark"] .sec-log      { --sec: #4ade80; --sec-soft: #0d2e1a; }
      [data-theme="dark"] .sec-sessions { --sec: #60a5fa; --sec-soft: #0f1f3d; }

      .tr-sec { border-top: 4px solid var(--sec); scroll-margin-top: calc(164px + env(safe-area-inset-top)); }
      .tr-sec-head { display: flex; align-items: center; gap: 10px; margin-bottom: 12px; min-height: 40px; }
      .tr-sec-head h2 { flex: 1; min-width: 0; }
      .tr-sec-ico { flex: none; width: 34px; height: 34px; border-radius: 10px; display: inline-flex; align-items: center; justify-content: center; background: var(--sec-soft); color: var(--sec); }
      .tr-sec-ico [class^="hero-"] { width: 20px; height: 20px; }
      .tr-sec-actions { display: flex; align-items: center; gap: 6px; }

      .tr-jump { position: sticky; top: calc(108px + env(safe-area-inset-top)); z-index: 40; display: flex; gap: 8px; overflow-x: auto; padding: 10px 16px; margin: 0 -16px; background: var(--surface2); scrollbar-width: none; -webkit-overflow-scrolling: touch; }
      .tr-jump::-webkit-scrollbar { display: none; }
      .tr-jump a { flex: none; display: inline-flex; align-items: center; gap: 6px; min-height: 38px; padding: 0 14px 0 10px; border-radius: 19px; background: var(--surface); border: 1.5px solid var(--border); color: var(--text); font-size: 15px; font-weight: 600; text-decoration: none; }
      .tr-jump a [class^="hero-"] { width: 18px; height: 18px; color: var(--sec); }
      .tr-jump a:active { background: var(--sec-soft); border-color: var(--sec); }

      /* Quiet buttons: actions shouldn't shout louder than the content */
      .tr-mini { display: inline-flex; align-items: center; gap: 4px; min-height: 36px; padding: 0 12px; border-radius: 18px; border: 1.5px solid var(--border); background: var(--surface); color: var(--text2); font-size: 14px; font-weight: 600; cursor: pointer; white-space: nowrap; }
      .tr-mini:active { background: var(--surface2); }
      .tr-mini.solid { background: var(--sec, var(--brand)); border-color: var(--sec, var(--brand)); color: #fff; }
      .tr-mini [class^="hero-"] { width: 16px; height: 16px; }
      .tr-mini.tr-icon-only { width: 36px; padding: 0; justify-content: center; }
      .tr-step-head + .tr-mark-row { border-top: none; padding-top: 0; }

      /* Rows inside a section (goals, working on) */
      .tr-item { padding: 14px 0; border-top: 1px solid var(--border); }
      .tr-item:first-of-type { border-top: none; padding-top: 2px; }
      .tr-item-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
      .tr-item-title { font-size: 17px; font-weight: 700; line-height: 1.3; }
      .tr-item-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 10px; margin-top: 4px; color: var(--text2); font-size: 14px; }
      .tr-item-meta [class^="hero-"] { width: 15px; height: 15px; vertical-align: -2px; margin-right: 2px; }
      .tr-item-note { margin-top: 6px; font-size: 15px; color: var(--text); white-space: pre-line; }
      .tr-item-actions { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; margin-top: 10px; }
      .tr-count { flex: none; padding: 3px 10px; border-radius: 12px; background: var(--sec-soft); color: var(--sec); font-size: 13px; font-weight: 700; white-space: nowrap; }
      .tr-item .tr-trend { margin-top: 8px; }
      .tr-item .tr-mark { width: 24px; height: 24px; font-size: 14px; border-radius: 6px; }
      .tr-more { margin-top: 6px; }
      .tr-more > summary { list-style: none; cursor: pointer; color: var(--text3); font-size: 14px; font-weight: 600; min-height: 40px; display: inline-flex; align-items: center; }
      .tr-more > summary::-webkit-details-marker { display: none; }
      .tr-more > summary::after { content: "▾"; margin-left: 6px; font-size: 12px; }
      .tr-more[open] > summary::after { content: "▴"; }

      /* Stage */
      .tr-next { margin-top: 16px; padding-top: 14px; border-top: 1px dashed var(--border); }
      .tr-next b { display: block; font-size: 16px; }

      /* ── TrAIner: a swipeable deck of question-and-answer cards ── */
      .tr-ai { font-weight: 800; color: #dc2626; }
      [data-theme="dark"] .tr-ai { color: #f87171; }
      .tr-deck { margin: 0 -18px; }
      .tr-deck-track { display: flex; gap: 12px; overflow-x: auto; scroll-snap-type: x mandatory; padding: 2px 18px 6px; scroll-padding: 0 18px; align-items: flex-start; scrollbar-width: none; -webkit-overflow-scrolling: touch; overscroll-behavior-x: contain; overflow-y: hidden; transition: height .25s ease; }
      .tr-deck-track::-webkit-scrollbar { display: none; }
      .tr-qa { flex: 0 0 100%; scroll-snap-align: start; scroll-snap-stop: always; border-radius: 14px; border: 1px solid var(--border); background: var(--surface); box-shadow: 0 1px 3px rgba(0,0,0,.06); overflow: hidden; }
      .tr-qa-q { padding: 12px 16px; background: var(--sec-soft); color: var(--text); }
      .tr-qa-label { display: block; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; color: var(--sec); margin-bottom: 2px; }
      .tr-qa-q p { font-size: 16px; font-weight: 600; line-height: 1.4; }
      .tr-qa-a { padding: 14px 16px 6px; }
      .tr-qa-foot { padding: 4px 16px 12px; font-size: 13px; color: var(--text3); }
      .tr-qa-foot details { display: inline; }
      .tr-qa-foot details[open] { display: block; }
      .tr-qa-foot details summary { cursor: pointer; list-style: none; display: inline; }
      .tr-qa-foot details summary::-webkit-details-marker { display: none; }
      .tr-qa-foot details ul { margin: 6px 0 0 18px; }
      .tr-qa-loading .tr-qa-a { color: var(--text2); display: flex; align-items: center; gap: 10px; padding-bottom: 16px; }
      .tr-dots-anim { display: inline-flex; gap: 4px; }
      .tr-dots-anim i { width: 7px; height: 7px; border-radius: 50%; background: var(--sec); animation: tr-pulse 1.2s infinite ease-in-out; }
      .tr-dots-anim i:nth-child(2) { animation-delay: .2s; }
      .tr-dots-anim i:nth-child(3) { animation-delay: .4s; }
      @keyframes tr-pulse { 0%, 80%, 100% { opacity: .25; transform: scale(.8); } 40% { opacity: 1; transform: scale(1); } }
      .tr-deck-nav { display: flex; align-items: center; justify-content: center; gap: 12px; margin-top: 8px; }
      .tr-deck-nav button { width: 36px; height: 36px; border-radius: 50%; border: 1.5px solid var(--border); background: var(--surface); color: var(--text2); font-size: 18px; line-height: 1; cursor: pointer; }
      .tr-deck-nav button:disabled { opacity: .35; cursor: default; }
      .tr-deck-dots { display: flex; gap: 6px; }
      .tr-deck-dots i { width: 8px; height: 8px; border-radius: 50%; background: var(--border); transition: background .2s, width .2s; }
      .tr-deck-dots i.on { background: var(--sec); width: 20px; border-radius: 4px; }
      .tr-deck-count { font-size: 13px; color: var(--text3); min-width: 44px; text-align: center; }

      .tr-prose { font-size: 17px; line-height: 1.6; color: var(--text); }
      .tr-prose p { margin: 0 0 12px; }
      .tr-prose ul, .tr-prose ol { margin: 0 0 12px; padding-left: 22px; display: grid; gap: 6px; }
      .tr-prose ul { list-style: disc; }
      .tr-prose ol { list-style: decimal; }
      .tr-prose li::marker { color: var(--sec, var(--brand)); }
      .tr-prose strong { font-weight: 700; }
      .tr-prose-h { font-weight: 700; }

      .tr-composer { margin-top: 14px; display: grid; gap: 8px; }
      .tr-composer textarea { width: 100%; min-height: 64px; padding: 12px 14px; border: 1.5px solid var(--border); border-radius: 12px; background: var(--surface2); color: var(--text); font-size: 16px; line-height: 1.4; resize: vertical; font-family: inherit; }
      .tr-composer textarea:focus { outline: none; border-color: var(--sec); }
      .tr-composer .tr-btn-primary { background: var(--sec); border-color: var(--sec); min-height: 50px; font-size: 17px; }
      .tr-ideas { margin-top: 2px; }
      .tr-ideas .tr-pills { margin-top: 4px; }
      .tr-fine { margin-top: 12px; font-size: 13px; color: var(--text3); }

      /* ── Log a session: numbered steps and one-tap rows ── */
      .tr-step { margin-bottom: 20px; }
      .tr-step-head { display: flex; align-items: baseline; gap: 8px; margin-bottom: 8px; font-size: 16px; font-weight: 700; color: var(--text); }
      .tr-step-head small { font-size: 14px; font-weight: 400; color: var(--text3); }
      .tr-step-n { flex: none; width: 24px; height: 24px; border-radius: 50%; background: var(--sec-soft); color: var(--sec); font-size: 13px; font-weight: 800; display: inline-flex; align-items: center; justify-content: center; transform: translateY(-1px); }
      .tr-inline { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
      .tr-inline input[type=date], .tr-inline input[type=number] { flex: 1 1 140px; min-width: 0; min-height: 44px; padding: 8px 12px; border: 1.5px solid var(--border); border-radius: 22px; background: var(--surface2); color: var(--text); font-size: 16px; }
      .tr-inline input[type=number] { flex: 0 1 110px; }
      .tr-quickstart { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; padding: 10px 12px; margin-bottom: 18px; border-radius: 12px; background: var(--sec-soft); }
      .tr-quickstart .tr-label { margin: 0 4px 0 0; color: var(--sec); }
      .sec-log .tr-pill input:checked + span { background: var(--sec); border-color: var(--sec); }
      [data-theme="dark"] .sec-log .tr-pill input:checked + span { color: #052e16; }
      .tr-act { margin: 0 0 10px; padding: 12px; border-radius: 12px; border: 1px solid var(--border); background: var(--surface2); display: grid; gap: 8px; }
      .tr-act > b { font-size: 16px; }
      .tr-seg { display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; border: 1.5px solid var(--border); border-radius: 12px; overflow: hidden; background: var(--surface); }
      .tr-seg .tr-pill + .tr-pill { border-left: 1.5px solid var(--border); }
      .tr-seg .tr-pill span { width: 100%; justify-content: center; border: none; border-radius: 0; min-height: 42px; padding: 0 6px; font-size: 15px; background: transparent; }
      .sec-log .tr-seg .tr-pill input:checked + span { background: var(--text2); color: var(--surface); }
      .sec-log .tr-seg .tr-pill.res-good input:checked + span, .sec-log .tr-seg .tr-pill.mk-better input:checked + span { background: #16a34a; color: #fff; }
      .sec-log .tr-seg .tr-pill.res-mixed input:checked + span { background: #d97706; color: #fff; }
      .sec-log .tr-seg .tr-pill.res-trouble input:checked + span, .sec-log .tr-seg .tr-pill.mk-worse input:checked + span { background: #dc2626; color: #fff; }
      .sec-log .tr-seg .tr-pill.mk-same input:checked + span { background: #6b7280; color: #fff; }
      .sec-log .tr-seg .tr-pill.mk-skip input:checked + span { background: var(--surface2); color: var(--text2); }
      .tr-mark-row { padding: 12px 0; border-top: 1px solid var(--border); display: grid; gap: 8px; }
      .tr-mark-row:first-of-type { border-top: none; padding-top: 0; }
      .tr-mark-row > b { font-size: 16px; }
      .sec-log .tr-btn-primary { background: var(--sec); border-color: var(--sec); }
      [data-theme="dark"] .sec-log .tr-btn-primary { color: #052e16; }

      /* ── Today ── */
      .tr-day-status { padding: 4px 12px; border-radius: 14px; font-size: 14px; font-weight: 700; white-space: nowrap; }
      .tr-day-status.st-work { background: var(--sec-soft); color: var(--sec); }
      .tr-day-status.st-rest { background: var(--surface2); color: var(--text2); border: 1px solid var(--border); }
      .tr-day-status.st-done { background: #dcfce7; color: #15803d; }
      [data-theme="dark"] .tr-day-status.st-done { background: #0d2e1a; color: #4ade80; }
      .tr-strip { display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; }
      .tr-strip-day { text-align: center; padding: 6px 0; border-radius: 10px; background: var(--surface2); border: 1.5px solid transparent; }
      .tr-strip-day small { display: block; font-size: 11px; font-weight: 700; color: var(--text3); text-transform: uppercase; letter-spacing: .02em; }
      .tr-strip-day span { display: block; font-size: 15px; font-weight: 800; color: var(--text3); margin-top: 2px; }
      .tr-strip-day.worked { background: var(--sec-soft); }
      .tr-strip-day.worked span { color: var(--sec); }
      .tr-strip-day.today { border-color: var(--sec); }
      .tr-today-reason { margin-top: 12px; font-size: 16px; }
      .tr-today-plan { margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--border); }
      .tr-today-focus { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 10px; padding: 3px 0; }
      .tr-today-focus b { font-size: 16px; }
      .tr-today-focus span { font-size: 14px; }
      .sec-today .tr-btn-primary { background: var(--sec); border-color: var(--sec); }
      [data-theme="dark"] .sec-today .tr-btn-primary { color: #042f2e; }

      /* ── Talk-to-log and the timer ── */
      .tr-voice { margin-bottom: 18px; padding: 12px; border-radius: 12px; border: 1.5px dashed #fca5a5; background: #fff7f7; display: grid; gap: 8px; }
      [data-theme="dark"] .tr-voice { border-color: #7f1d1d; background: #1f1215; }
      .tr-voice-head { display: flex; align-items: center; gap: 8px; font-size: 16px; font-weight: 700; }
      .tr-voice-head [class^="hero-"] { width: 20px; height: 20px; color: #dc2626; }
      .tr-voice textarea { width: 100%; padding: 10px 12px; border: 1.5px solid var(--border); border-radius: 10px; background: var(--surface); color: var(--text); font-size: 16px; line-height: 1.4; font-family: inherit; resize: vertical; }
      .tr-voice-actions { display: flex; align-items: center; gap: 8px; }
      .tr-voice .tr-mini.solid { --sec: #dc2626; min-height: 40px; padding: 0 16px; }
      .tr-voice .tr-dots-anim i { background: #fff; }
      .tr-voice-note { font-size: 14px; color: var(--text2); }
      .tr-voice-note.ok { color: #15803d; font-weight: 600; }
      .tr-voice-note.err { color: #dc2626; font-weight: 600; }
      [data-theme="dark"] .tr-voice-note.ok { color: #4ade80; }
      .tr-timer { margin-top: 10px; display: inline-flex; align-items: center; gap: 8px; min-height: 44px; padding: 0 16px; border-radius: 22px; border: 1.5px dashed var(--border); background: var(--surface); color: var(--text2); font-size: 15px; font-weight: 600; cursor: pointer; font-variant-numeric: tabular-nums; }
      .tr-timer [class^="hero-"] { width: 18px; height: 18px; }
      .tr-timer.running { border-style: solid; border-color: var(--sec); background: var(--sec-soft); color: var(--sec); }

      /* ── Training overview cards ── */
      .tr-hc-stage { margin-top: 2px; font-size: 15px; font-weight: 600; color: var(--brand); line-height: 1.3; }
      .tr-hc-last { margin-top: 14px; padding: 10px 12px; border-radius: 12px; background: var(--surface2); border-left: 4px solid #2563eb; }
      [data-theme="dark"] .tr-hc-last { border-left-color: #60a5fa; }
      .tr-hc-last .tr-label { margin-bottom: 2px; }
      .tr-hc-last b { font-size: 16px; }
      .tr-hc-last p { font-size: 15px; color: var(--text2); margin-top: 2px; }
      .tr-hc-sum { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 10px; }
      .tr-hc-box { padding: 10px 12px; border-radius: 12px; background: var(--surface2); min-width: 0; }
      .tr-hc-box .tr-label { margin-bottom: 4px; }
      .tr-hc-big { font-size: 22px; font-weight: 800; line-height: 1.1; }
      .tr-hc-big small { font-size: 14px; font-weight: 600; color: var(--text2); }
      .tr-hc-sub { font-size: 14px; color: var(--text2); margin-top: 2px; line-height: 1.3; }
      .tr-hc-goal { font-size: 15px; font-weight: 700; line-height: 1.25; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
      .tr-hc-over { color: #dc2626; }

      /* ── Session history: a date badge, then what happened ── */
      .tr-sess { display: grid; grid-template-columns: 48px 1fr; gap: 12px; padding: 14px 0; border-top: 1px solid var(--border); }
      .tr-sess:first-of-type { border-top: none; padding-top: 2px; }
      .tr-date { width: 48px; border-radius: 10px; background: var(--sec-soft); color: var(--sec); text-align: center; padding: 6px 0 5px; line-height: 1.1; align-self: start; }
      .tr-date small { display: block; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; }
      .tr-date b { display: block; font-size: 20px; font-weight: 800; }
      .tr-sess-title { font-size: 16px; font-weight: 700; }
      .tr-sess-title span { font-weight: 400; color: var(--text2); }
      .tr-sess-line { font-size: 15px; color: var(--text2); margin-top: 3px; }
      .tr-sess-note { margin-top: 6px; font-size: 15px; white-space: pre-line; }
      .tr-sess-actions { display: flex; gap: 4px; margin-top: 4px; }
      .tr-sess-actions .tr-link-btn { padding: 0 12px 0 0; }
    </style>
    """
  end
end
