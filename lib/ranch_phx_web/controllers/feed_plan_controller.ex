defmodule RanchPhxWeb.FeedPlanController do
  @moduledoc """
  The feed plan as a page to print or save as a PDF (`print`, logged in), and the same
  page at its secret share link (`shared`, no login; only while sharing is on).
  """
  use RanchPhxWeb, :controller
  alias RanchPhx.{Animals, FeedPlans}
  alias RanchPhx.Animals.Animal

  def print(conn, %{"id" => id}) do
    animal = Animals.get_animal!(id)
    render_plan(conn, animal, FeedPlans.get_or_new(animal.id), false)
  end

  def shared(conn, %{"token" => token}) do
    case FeedPlans.get_shared(token) do
      nil ->
        conn
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> put_resp_content_type("text/html")
        |> send_resp(404, """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Feed plan</title></head>
        <body style="font-family:-apple-system,Helvetica,sans-serif;padding:40px 20px;text-align:center;color:#333">
        <h2>This feed plan isn't shared right now.</h2><p>Ask the owner for a new link.</p></body></html>
        """)

      plan ->
        conn
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> put_resp_header("cache-control", "no-store")
        |> render_plan(plan.animal, plan, true)
    end
  end

  defp render_plan(conn, animal, plan, public?) do
    name = Animal.display_name(animal)

    conn
    |> put_root_layout(false)
    |> put_layout(html: {RanchPhxWeb.Layouts, :print})
    |> render(:plan,
      animal: animal,
      name: name,
      plan: plan,
      sections: FeedPlans.filled(plan),
      care: FeedPlans.current_care(animal.id),
      public: public?,
      report_title: "#{name} feed plan"
    )
  end
end
