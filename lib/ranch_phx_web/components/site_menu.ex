defmodule RanchPhxWeb.SiteMenu do
  @moduledoc """
  The full menu: every page in the app in one place, so anything can be found from
  anywhere. `site_menu/1` is the sheet itself (rendered once per page by `AppNav`),
  opened by `open/0`; `site_links/1` is just the rows, which the animal page's ⋯ sheet
  puts under that animal's own tabs and pages.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import RanchPhxWeb.CoreComponents, only: [icon: 1]

  @doc "Opens the full menu."
  def open(js \\ %JS{}),
    do: js |> JS.show(to: "#site-menu", display: "flex") |> JS.show(to: "#site-menu-bg")

  def close(js \\ %JS{}), do: js |> JS.hide(to: "#site-menu") |> JS.hide(to: "#site-menu-bg")

  attr :superuser, :boolean, default: false

  attr :close, JS,
    default: %JS{},
    doc: "runs before following a link (closes the sheet the rows sit in)"

  def site_links(assigns) do
    ~H"""
    <div class="sm-group">The ranch</div>
    <.row href="/" icon="hero-squares-2x2" label="Animals" />
    <.row href="/training" icon="hero-academic-cap" label="Training" />
    <.row href="/training/lists" icon="hero-list-bullet" label="Training lists" />
    <.row href="/conformation" icon="hero-viewfinder-circle" label="Evaluate (conformation)" />
    <.row :if={@superuser} href="/voice" icon="hero-microphone" label="Voice log & Siri" />
    <.row href="/notifications" icon="hero-bell" label="Reminders & notifications" />
    <.row href="/barn.html" icon="hero-signal-slash" label="Barn mode (no signal)" live={false} />
    <.row
      href="/offline.html"
      icon="hero-identification"
      label="Papers saved on this phone"
      live={false}
    />

    <div class="sm-group">Settings</div>
    <.row :if={@superuser} href="/admin/settings" icon="hero-cog-6-tooth" label="Settings" />
    <.row :if={@superuser} href="/admin/users" icon="hero-users" label="Users" />
    <.row :if={@superuser} href="/admin/backups" icon="hero-cloud-arrow-up" label="Backups" />
    <button type="button" class="sm-row" phx-click={JS.dispatch("ranch:toggle-theme")}>
      <.icon name="hero-moon" /> Light / dark
    </button>
    <.row href="https://portal.gimelranch.com" icon="hero-home" label="Portal" live={false} />
    <.link class="sm-row" href="/users/log-out" method="delete">
      <.icon name="hero-arrow-right-on-rectangle" /> Log out
    </.link>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :live, :boolean, default: true

  defp row(assigns) do
    ~H"""
    <a :if={@live} class="sm-row" href={@href} data-phx-link="redirect" data-phx-link-state="push">
      <.icon name={@icon} /> {@label}
    </a>
    <a :if={!@live} class="sm-row" href={@href}><.icon name={@icon} /> {@label}</a>
    """
  end

  attr :superuser, :boolean, default: false

  def site_menu(assigns) do
    ~H"""
    <style>
      .sm-bg { position: fixed; inset: 0; z-index: 600; background: rgba(0,0,0,.45); }
      .sm-sheet { position: fixed; left: 0; right: 0; bottom: 0; z-index: 610; flex-direction: column; max-height: 88vh; overflow-y: auto; background: var(--surface); border-radius: 18px 18px 0 0; padding: 6px 8px calc(10px + env(safe-area-inset-bottom)); box-shadow: 0 -6px 30px rgba(0,0,0,.25); }
      @media (min-width: 601px) { .sm-sheet { left: auto; right: 12px; bottom: auto; top: calc(64px + env(safe-area-inset-top)); width: 360px; border-radius: 16px; } }
      .sm-handle { width: 40px; height: 5px; border-radius: 3px; background: var(--border); margin: 6px auto 2px; flex: none; }
      .sm-group { font-size: 12px; font-weight: 800; text-transform: uppercase; letter-spacing: .06em; color: var(--text3); padding: 12px 12px 4px; }
      .sm-row { display: flex; align-items: center; gap: 14px; width: 100%; min-height: 50px; padding: 0 12px; border: none; border-radius: 12px; background: none; color: var(--text); font: inherit; font-size: 16px; font-weight: 600; text-align: left; text-decoration: none; cursor: pointer; flex: none; }
      .sm-row:active, .sm-row:hover { background: var(--surface2); }
      .sm-row.on { color: var(--brand); }
      .sm-row [class^="hero-"] { width: 21px; height: 21px; color: var(--brand); flex: none; }
      .sm-close { justify-content: center; margin-top: 8px; background: var(--surface2); }
    </style>
    <div id="site-menu-bg" class="sm-bg" style="display:none" phx-click={close()}></div>
    <nav id="site-menu" class="sm-sheet" style="display:none" aria-label="All pages">
      <div class="sm-handle"></div>
      <.site_links superuser={@superuser} />
      <button type="button" class="sm-row sm-close" phx-click={close()}>Close</button>
    </nav>
    """
  end
end
