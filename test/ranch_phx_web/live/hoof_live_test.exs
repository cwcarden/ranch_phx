defmodule RanchPhxWeb.HoofLiveTest do
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.Animals

  setup :register_and_log_in_user

  setup do
    {:ok, animal} = Animals.create_animal(%{name: "Asher", kind: "horse"})
    %{animal: animal}
  end

  test "measure a hoof: the numbers, then the marked-up photo, become a hoof entry",
       %{conn: conn, animal: animal} do
    {:ok, show, _} = live(conn, ~p"/animals/#{animal.id}")
    assert has_element?(show, "#hooves", "Measure toe and pastern angles")

    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")
    view |> element("#pick-RF") |> render_click()

    render_hook(view, "hoof_measured", %{
      "foot" => "RF",
      "toe" => 52.0,
      "pastern" => 49.0,
      "date" => Date.to_iso8601(Date.utc_today()),
      "note" => "4 weeks since trim",
      "points" => %{"ground" => [%{"x" => 700, "y" => 1000}, %{"x" => 1100, "y" => 1000}]}
    })

    photo =
      file_input(view, "#hoof-upload-form", :hoof, [
        %{name: "hoof-RF.jpg", content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
      ])

    render_upload(photo, "hoof-RF.jpg")

    assert has_element?(view, "#foot-RF", "52°")
    assert has_element?(view, "#foot-RF", "Hoof and pastern line up")
    assert has_element?(view, "#hoof-history", "4 weeks since trim")

    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert event.event_type == "hoof"
    assert event.metadata["toe"] == 52.0
    assert [url] = event.photo_urls
    assert url =~ "/uploads/animals/#{animal.id}/hooves/"
    File.rm(Path.join(Application.app_dir(:ranch_phx, "priv/static"), url))

    {:ok, show, _} = live(conn, ~p"/animals/#{animal.id}")
    assert has_element?(show, "#hooves .hc-foot", "52°")
  end

  test "a line that makes no angle is refused", %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")
    render_hook(view, "hoof_measured", %{"foot" => "LF", "toe" => 0})
    assert render(view) =~ "didn&#39;t make an angle"
  end
end
