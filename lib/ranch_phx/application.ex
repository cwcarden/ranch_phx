defmodule RanchPhx.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        RanchPhxWeb.Telemetry,
        RanchPhx.Repo,
        {DNSCluster, query: Application.get_env(:ranch_phx, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: RanchPhx.PubSub},
        {Finch, name: RanchPhx.Finch},
        RanchPhx.RanchAsk.Memory,
        RanchPhxWeb.Endpoint
      ] ++
        if(Application.get_env(:ranch_phx, :push_reminders, true),
          do: [RanchPhx.Push.Reminders],
          else: []
        ) ++
        if(Application.get_env(:ranch_phx, :nightly_backup, true),
          do: [RanchPhx.Backup.Nightly],
          else: []
        )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RanchPhx.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Older versions saved some photos inside the release, which each deploy rebuilds.
    # Copy any of those into the permanent uploads folder (copies only, never deletes).
    if Application.get_env(:ranch_phx, :adopt_release_uploads, true) do
      Task.start(fn ->
        n = RanchPhx.Storage.adopt_release_files()
        if n > 0, do: Logger.info("Copied #{n} uploaded file(s) out of the release")
      end)
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RanchPhxWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
