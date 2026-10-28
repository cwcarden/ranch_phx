defmodule RanchPhxWeb.HoofReportTest do
  use RanchPhxWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias RanchPhx.Animals

  setup :register_and_log_in_user

  test "farrier report: each foot's photos and what they mean, plus hoof-care records",
       %{conn: conn} do
    {:ok, animal} = Animals.create_animal(%{name: "Asher", kind: "horse"})

    for attrs <- [
          %{
            "metadata" => %{"foot" => "LF", "toe" => 46.0, "pastern" => 53.0},
            "photo_urls" => ["/uploads/x/side.jpg"]
          },
          %{
            "metadata" => %{
              "view" => "sole",
              "foot" => "LF",
              "toe_share" => 51.0,
              "sides" => 52.0,
              "heels" => 1.0,
              "frog" => 1.0,
              "ratio" => 0.97
            },
            "photo_urls" => ["/uploads/x/sole.jpg"]
          },
          %{"metadata" => %{"foot" => "RH", "toe" => 54.0}}
        ] do
      {:ok, _} =
        Animals.create_event(
          Map.merge(
            %{
              "animal_id" => animal.id,
              "event_type" => "hoof",
              "title" => "Hoof",
              "event_date" => ~D[2026-10-20]
            },
            attrs
          )
        )
    end

    html =
      conn
      |> get(~p"/animals/#{animal.id}/report?#{[kind: "farrier", profile: "1", hooves: "1"]}")
      |> html_response(200)

    assert html =~ "Gimel Ranch Farrier Report"
    assert html =~ "<title>Report — Asher farrier</title>"
    assert html =~ ~s(src="/uploads/x/side.jpg")
    assert html =~ ~s(src="/uploads/x/sole.jpg")
    assert html =~ "lower than usual for a front foot"
    assert html =~ "Broken back"
    assert html =~ "the widest part is near the middle"
    assert html =~ "Right hind"
    assert html =~ "All measurements"
    assert html =~ ~s(<td class="hf-thumb"><img src="/uploads/x/sole.jpg")

    # Not asked for: no hoof section.
    html = conn |> get(~p"/animals/#{animal.id}/report?profile=1") |> html_response(200)
    refute html =~ ~s(id="rpt-hooves")
  end

  test "picking only Hoof Care records brings in the hoof measurements too", %{conn: conn} do
    {:ok, animal} = Animals.create_animal(%{name: "Asher", kind: "horse"})

    {:ok, _} =
      Animals.create_event(%{
        "animal_id" => animal.id,
        "event_type" => "hoof",
        "title" => "Hoof",
        "event_date" => ~D[2026-10-20],
        "metadata" => %{"foot" => "LF", "toe" => 52.0},
        "photo_urls" => ["/uploads/x/side.jpg"]
      })

    html =
      conn
      |> get(~p"/animals/#{animal.id}/report?records=1&record_cats[]=hoof_care")
      |> html_response(200)

    assert html =~ ~s(id="rpt-hooves")
    assert html =~ ~s(src="/uploads/x/side.jpg")
  end

  test "the report popup has select all and deselect all", %{conn: conn} do
    {:ok, animal} = Animals.create_animal(%{name: "Asher", kind: "horse"})
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    html = render_click(view, "open_report", %{})
    assert html =~ ~s(id="rpt-select-all")
    assert html =~ ~s(id="rpt-select-none")
    assert html =~ ~s(name="hooves")
  end
end
