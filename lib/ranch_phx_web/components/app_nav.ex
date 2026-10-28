defmodule RanchPhxWeb.AppNav do
  @moduledoc """
  The bar at the top of every page: the ranch home button, Animals | Training, and the
  light/dark switch. Each page's own title bar sits under it.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import RanchPhxWeb.CoreComponents, only: [icon: 1]

  attr :active, :atom, default: nil, doc: ":animals, :training, or nil"

  attr :flash, :map, default: nil, doc: "pass @flash to show saved/error notices as a toast"

  attr :detail, :boolean,
    default: false,
    doc:
      "a page under another one (an animal, a training book): on phones the bar hides and the page's own bar, with its back button, sits at the top"

  def app_nav(assigns) do
    ~H"""
    <style>
      :root { --an-h: 52px; }
      .an-bar { position: sticky; top: 0; z-index: 120; height: 52px; display: flex; align-items: center; gap: 10px; padding: 0 12px; padding-top: env(safe-area-inset-top); box-sizing: content-box; background: var(--surface); border-bottom: 1px solid var(--border); }
      .an-home { display: inline-flex; align-items: center; gap: 8px; min-height: 44px; color: var(--brand); font-size: 17px; font-weight: 800; text-decoration: none; white-space: nowrap; }
      .an-home [class^="hero-"] { width: 24px; height: 24px; }
      .an-mark { flex: none; width: 28px; height: 28px; background: currentColor; -webkit-mask: url(/images/brand-mark.png) center / contain no-repeat; mask: url(/images/brand-mark.png) center / contain no-repeat; }
      .an-tabs { display: flex; gap: 4px; padding: 3px; margin: 0 auto; border-radius: 12px; background: var(--surface2); border: 1px solid var(--border); }
      .an-tabs a { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; padding: 0 14px; border-radius: 9px; color: var(--text2); font-size: 15px; font-weight: 700; text-decoration: none; white-space: nowrap; }
      .an-tabs a [class^="hero-"] { width: 17px; height: 17px; }
      .an-tabs a.on { background: var(--brand); color: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.15); }
      .an-theme { flex: none; width: 40px; height: 40px; border-radius: 50%; border: 1.5px solid var(--border); background: var(--surface); color: var(--text2); display: inline-flex; align-items: center; justify-content: center; cursor: pointer; }
      .an-theme [class^="hero-"] { width: 18px; height: 18px; }
      .an-bell { margin-right: -4px; }
      @media (max-width: 400px) { .an-tabs a { padding: 0 10px; font-size: 14px; } .an-bar { gap: 6px; } }
      @media (max-width: 480px) { .an-home .an-name { display: none; } .an-tabs a { padding: 0 12px; } }
      .an-toasts { position: fixed; left: 12px; right: 12px; bottom: calc(84px + env(safe-area-inset-bottom)); z-index: 500; display: flex; flex-direction: column; align-items: center; gap: 8px; pointer-events: none; }
      .an-toast { pointer-events: auto; display: inline-flex; align-items: center; gap: 10px; max-width: 520px; min-height: 48px; padding: 10px 16px; border-radius: 14px; border: none; font: inherit; font-size: 15px; font-weight: 600; text-align: left; color: #fff; box-shadow: 0 10px 30px rgba(0,0,0,.25); cursor: pointer; animation: an-toast-in .2s ease-out; }
      .an-toast [class^="hero-"] { width: 20px; height: 20px; flex: none; }
      .an-info { background: #15803d; }
      .an-error { background: #b91c1c; }
      @keyframes an-toast-in { from { transform: translateY(12px); opacity: 0; } to { transform: none; opacity: 1; } }
    </style>
    <style :if={@detail}>
      @media (max-width: 600px) {
        :root { --an-h: 0px; }
        .an-bar { display: none; }
        /* Covers the strip under the iPhone's status bar, so the page doesn't show through above the top bar. */
        body::before { content: ""; position: fixed; top: 0; left: 0; right: 0; height: env(safe-area-inset-top); background: var(--surface); z-index: 130; }
      }
    </style>
    <div :if={@flash} class="an-toasts" aria-live="polite">
      <button
        :for={
          {kind, msg} <- [
            info: Phoenix.Flash.get(@flash, :info),
            error: Phoenix.Flash.get(@flash, :error)
          ]
        }
        :if={msg}
        type="button"
        class={["an-toast", "an-#{kind}"]}
        id={"toast-#{kind}"}
        phx-click={JS.push("lv:clear-flash", value: %{key: kind}) |> JS.hide(to: "#toast-#{kind}")}
        phx-hook="Toast"
      >
        <.icon name={if kind == :info, do: "hero-check-circle", else: "hero-exclamation-triangle"} />
        <span>{msg}</span>
      </button>
    </div>
    <nav class="an-bar" id="app-nav" aria-label="Main">
      <a href="/" class="an-home" aria-label="Gimel Ranch home">
        <span class="an-mark" aria-hidden="true"></span><span class="an-name">Gimel Ranch</span>
      </a>
      <div class="an-tabs">
        <a href="/" class={@active == :animals && "on"} aria-current={@active == :animals && "page"}>
          <.icon name="hero-squares-2x2" /> Animals
        </a>
        <a
          href="/training"
          class={@active == :training && "on"}
          aria-current={@active == :training && "page"}
        >
          <.icon name="hero-academic-cap" /> Training
        </a>
      </div>
      <a href="/notifications" class="an-theme an-bell" aria-label="Notifications">
        <.icon name="hero-bell" />
      </a>
      <button
        type="button"
        class="an-theme"
        phx-click={JS.dispatch("ranch:toggle-theme")}
        aria-label="Switch light or dark"
      >
        <.icon name="hero-moon" />
      </button>
    </nav>
    """
  end
end
