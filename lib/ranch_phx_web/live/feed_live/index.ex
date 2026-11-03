defmodule RanchPhxWeb.FeedLive.Index do
  @moduledoc """
  An animal's feed plan: write it, print or share it as a PDF, and turn a live link
  on or off for whoever is feeding while you're away (see `RanchPhxWeb.FeedShareController`).
  """
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents, only: [styles: 1, topbar: 1]
  alias RanchPhx.{Animals, FeedPlans}
  alias RanchPhx.Accounts.Scope
  alias RanchPhx.Animals.Animal

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    animal = Animals.get_animal!(id)
    plan = FeedPlans.get_or_new(animal.id)

    {:ok,
     socket
     |> assign(:page_title, "#{Animal.display_name(animal)}'s feed plan")
     |> assign(:animal, animal)
     |> assign(:is_superuser, Scope.superuser?(socket.assigns.current_scope))
     |> assign(:base, nil)
     |> assign(:dirty, false)
     |> assign(:care, FeedPlans.current_care(animal.id))
     |> put_plan(plan)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    u = URI.parse(uri)
    port = if u.port in [80, 443, nil], do: "", else: ":#{u.port}"
    {:noreply, assign(socket, :base, "#{u.scheme}://#{u.host}#{port}")}
  end

  defp put_plan(socket, plan),
    do: socket |> assign(:plan, plan) |> assign(:sections, plan.sections || [])

  @impl true
  def handle_event("edit", %{"sections" => params}, socket),
    do: {:noreply, socket |> assign(:sections, from_params(params)) |> assign(:dirty, true)}

  def handle_event("edit", _params, socket), do: {:noreply, socket}

  def handle_event("save", params, socket) do
    with true <- socket.assigns.is_superuser,
         {:ok, plan} <-
           FeedPlans.save(socket.assigns.plan, from_params(params["sections"] || %{})) do
      {:noreply,
       socket |> put_plan(plan) |> assign(:dirty, false) |> put_flash(:info, "Feed plan saved.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't save the feed plan.")}
    end
  end

  def handle_event("add", _params, socket),
    do:
      {:noreply,
       socket
       |> assign(:sections, socket.assigns.sections ++ [%{"title" => "", "body" => ""}])
       |> assign(:dirty, true)}

  def handle_event("remove", %{"i" => i}, socket),
    do:
      {:noreply,
       socket
       |> assign(:sections, List.delete_at(socket.assigns.sections, String.to_integer(i)))
       |> assign(:dirty, true)}

  def handle_event("move", %{"i" => i, "by" => by}, socket) do
    i = String.to_integer(i)
    j = i + String.to_integer(by)
    list = socket.assigns.sections

    if j < 0 or j >= length(list) do
      {:noreply, socket}
    else
      a = Enum.at(list, i)
      b = Enum.at(list, j)

      {:noreply,
       socket
       |> assign(:sections, list |> List.replace_at(i, b) |> List.replace_at(j, a))
       |> assign(:dirty, true)}
    end
  end

  def handle_event("share", %{"on" => on}, socket) do
    with true <- socket.assigns.is_superuser,
         {:ok, plan} <- FeedPlans.set_sharing(socket.assigns.plan, on == "true") do
      # A brand-new plan gets saved along with what's been typed so far.
      plan =
        if socket.assigns.dirty or is_nil(socket.assigns.plan.id) do
          {:ok, p} = FeedPlans.save(plan, socket.assigns.sections)
          p
        else
          plan
        end

      {:noreply,
       socket
       |> assign(:plan, plan)
       |> assign(:dirty, false)
       |> put_flash(
         :info,
         if(plan.share_on,
           do: "Link is on. Anyone with it can see this plan.",
           else: "Link is off. It won't open for anyone now."
         )
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't change sharing.")}
    end
  end

  def handle_event("new_link", _params, socket) do
    with true <- socket.assigns.is_superuser,
         {:ok, plan} <- FeedPlans.new_link(socket.assigns.plan) do
      {:noreply,
       socket
       |> assign(:plan, plan)
       |> put_flash(:info, "New link made. The old one no longer works.")}
    else
      _ -> {:noreply, socket}
    end
  end

  defp from_params(params) when is_map(params) do
    params
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_, s} -> %{"title" => s["title"] || "", "body" => s["body"] || ""} end)
  end

  defp from_params(_), do: []

  def share_url(base, plan), do: "#{base}/share/feed/#{plan.share_token}"

  def placeholder("Emergency contacts"), do: "Owner: name and phone\nVet: name and phone"

  def placeholder("Morning feed"),
    do: "2 lb ration balancer\nWhere to find it: white feed bin in the feed room"

  def placeholder("Other notes"),
    do: "Anything else: turnout, blanketing, gate codes, what to watch for"

  def placeholder("Hay"), do: "Keep the hay bin full\nTypical: refill about every day and a half"

  def placeholder(_),
    do:
      "Write it the way you'd tell them. A line like \"Where: tack room\" shows the part before the colon in bold."
end
