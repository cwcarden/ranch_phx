defmodule RanchPhxWeb.Router do
  use RanchPhxWeb, :router

  import RanchPhxWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RanchPhxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Barn mode (/barn.html): the app's own session, JSON in and out. It's a plain page
  # with no form token, so these check the request came from the app's own origin.
  pipeline :barn do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_flash
    plug :fetch_current_scope_for_user
  end

  scope "/api/barn", RanchPhxWeb do
    pipe_through [:barn, :require_authenticated_user]

    get "/snapshot", BarnController, :snapshot
    post "/sync", BarnController, :sync
    post "/photo", BarnController, :photo
  end

  # Protected animal routes — require login
  scope "/", RanchPhxWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{RanchPhxWeb.UserAuth, :ensure_authenticated}] do
      live "/",                    AnimalLive.Index,  :index
      live "/animals/:id",         AnimalLive.Show,   :show
      live "/animals/:id/hooves",  HoofLive.Index,    :index
      live "/training",            TrainingLive.Index, :index
      live "/training/lists",      TrainingLive.Lists, :index
      live "/training/:id",        TrainingLive.Book,  :show
      live "/voice",               VoiceLive.Index,    :index
      live "/notifications",       NotificationsLive.Index, :index
      live "/conformation",        ConformationLive.Index, :index
    end

    get "/animals/:id/report", AnimalReportController, :show
  end

  # The Siri Shortcut posts here with its own key (no browser login).
  scope "/api", RanchPhxWeb do
    pipe_through :api

    post "/voice-log", VoiceLogController, :create
  end

  # Admin routes — superuser only
  scope "/admin", RanchPhxWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_superuser,
      on_mount: [{RanchPhxWeb.UserAuth, :ensure_superuser}] do
      live "/users",    AdminLive.Users,   :index
      live "/settings", SettingsLive.Index, :index
      live "/backups",  BackupLive.Index,  :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox in development
  if Application.compile_env(:ranch_phx, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RanchPhxWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", RanchPhxWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", RanchPhxWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", RanchPhxWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
