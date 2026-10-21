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

      .tr-topbar { position: sticky; top: 0; z-index: 50; height: 56px; display: flex; align-items: center; gap: 12px; padding: 0 16px; background: var(--surface); border-bottom: 1px solid var(--border); }
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
    </style>
    """
  end
end
