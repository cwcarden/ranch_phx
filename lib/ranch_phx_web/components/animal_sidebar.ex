defmodule RanchPhxWeb.AnimalSidebar do
  @moduledoc """
  On wide screens (an iPad sideways, a computer), the animal page keeps every animal
  in a list down the left, like Mail: tap one to open it on the same tab. Hidden on
  phones and an iPad held upright.
  """
  use Phoenix.Component
  import RanchPhxWeb.CoreComponents, only: [icon: 1]
  alias RanchPhx.Animals
  alias RanchPhx.Animals.{CareSchedule, Insights}

  @doc "The sidebar rows: `%{animal, alert: {:over | :soon | :now, text} | nil}`."
  def rows do
    animals = Animals.list_animals()
    today = Date.utc_today()
    inputs = animals |> Enum.map(& &1.id) |> Animals.insight_inputs()

    animals
    |> Enum.sort_by(&{&1.status != "active", !&1.is_favorite, String.downcase(&1.name || "")})
    |> Enum.map(fn a ->
      records = get_in(inputs, [a.id, :records]) || []
      course = records |> CareSchedule.active_courses(today) |> Enum.find(&(not &1.finished?))

      alert =
        cond do
          course && course.today_i && !course.today_given? ->
            {:now, "#{course.record.title}: day #{course.today_i + 1} of #{course.total}"}

          care = Insights.care_alert(records, today) ->
            {if(care.days < 0, do: :over, else: :soon),
             "#{care.record.title} #{if care.days < 0, do: "overdue", else: "due in #{care.days}d"}"}

          true ->
            nil
        end

      %{animal: a, alert: alert}
    end)
  end

  attr :rows, :list, required: true
  attr :current, :integer, required: true
  attr :tab, :string, default: "overview"

  def animal_sidebar(assigns) do
    ~H"""
    <aside class="as-side" aria-label="Animals">
      <div class="as-head">
        <a href="/" data-phx-link="redirect" data-phx-link-state="push" class="as-all">All animals</a>
        <span class="as-count">{length(@rows)}</span>
      </div>
      <nav class="as-list">
        <.link
          :for={%{animal: a, alert: alert} <- @rows}
          navigate={"/animals/#{a.id}" <> if(@tab != "overview", do: "?tab=#{@tab}", else: "")}
          class={["as-row", a.id == @current && "on", a.status != "active" && "dim"]}
          id={"side-#{a.id}"}
          aria-current={a.id == @current && "page"}
        >
          <span class="as-pic">
            <img :if={a.cover_photo_url} src={a.cover_photo_url} alt="" loading="lazy" />
            <span :if={!a.cover_photo_url}>{String.first(a.name || "?")}</span>
          </span>
          <span class="as-main">
            <b>
              {a.name}<.icon :if={a.is_favorite} name="hero-star-solid" class="as-fav" />
            </b>
            <small :if={!alert}>
              {[
                a.kind && String.capitalize(a.kind),
                a.status != "active" && String.capitalize(a.status)
              ]
              |> Enum.filter(& &1)
              |> Enum.join(" · ")}
            </small>
            <small :if={alert} class={"as-alert #{elem(alert, 0)}"}>{elem(alert, 1)}</small>
          </span>
        </.link>
      </nav>
    </aside>
    """
  end
end
