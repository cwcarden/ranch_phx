defmodule RanchPhx.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RanchPhxWeb.Telemetry,
      RanchPhx.Repo,
      {DNSCluster, query: Application.get_env(:ranch_phx, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RanchPhx.PubSub},
      {Finch, name: RanchPhx.Finch},
      RanchPhx.RanchAsk.Memory,
      RanchPhxWeb.Endpoint
    ] ++ if(Application.get_env(:ranch_phx, :push_reminders, true), do: [RanchPhx.Push.Reminders], else: []) ++
      if(Application.get_env(:ranch_phx, :nightly_backup, true), do: [RanchPhx.Backup.Nightly], else: [])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RanchPhx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RanchPhxWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
