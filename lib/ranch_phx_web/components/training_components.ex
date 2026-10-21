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
    </style>
    """
  end
end
