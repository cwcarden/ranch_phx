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

  test "saves with only the toe line (no pastern drawn)", %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")

    render_hook(view, "hoof_measured", %{
      "foot" => "LF",
      "toe" => 53.5,
      "pastern" => nil,
      "date" => Date.to_iso8601(Date.utc_today()),
      "note" => "",
      "points" => %{"ground" => [], "wall" => [], "pastern" => []}
    })

    photo =
      file_input(view, "#hoof-upload-form", :hoof, [
        %{name: "hoof-LF.jpg", content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
      ])

    render_upload(photo, "hoof-LF.jpg")
    assert has_element?(view, "#foot-LF", "53.5°")

    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert event.metadata["pastern"] == nil
    File.rm(Path.join(Application.app_dir(:ranch_phx, "priv/static"), hd(event.photo_urls)))
  end

  test "sole view: the balance numbers, then the photo, become a sole entry with a summary",
       %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")
    view |> element("#view-sole") |> render_click()
    assert has_element?(view, "#foot-picker[data-view=sole]")
    assert has_element?(view, "#tips-sole")
    view |> element("#pick-LF") |> render_click()

    render_hook(view, "hoof_measured", %{
      "view" => "sole",
      "foot" => "LF",
      "toe_share" => 58.2,
      "sides" => 51.0,
      "heels" => 1.5,
      "frog" => 2.0,
      "ratio" => 0.98,
      "date" => Date.to_iso8601(Date.utc_today()),
      "note" => "",
      "points" => %{"toe" => [%{"x" => 500, "y" => 100}]}
    })

    photo =
      file_input(view, "#hoof-upload-form", :hoof, [
        %{name: "hoof-LF-sole.jpg", content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
      ])

    render_upload(photo, "hoof-LF-sole.jpg")

    # Opens straight to what it means.
    assert has_element?(view, "#hoof-summary", "Toe 58.2% / heel 41.8%")
    assert has_element?(view, "#hoof-summary", "long toe or heels run forward")
    assert has_element?(view, "#hoof-summary", "even side to side")
    assert has_element?(view, "#foot-LF", "Sole: worth a look")
    assert has_element?(view, "#hoof-history", "Left front sole")

    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert event.metadata["view"] == "sole"
    assert event.title =~ "Left front sole: Toe 58.2%"
    File.rm(Path.join(Application.app_dir(:ranch_phx, "priv/static"), hd(event.photo_urls)))
  end

  test "side view summary after saving explains the angles", %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")

    render_hook(view, "hoof_measured", %{
      "foot" => "RF",
      "toe" => 46.0,
      "pastern" => 53.0,
      "date" => Date.to_iso8601(Date.utc_today()),
      "points" => %{}
    })

    photo =
      file_input(view, "#hoof-upload-form", :hoof, [
        %{name: "hoof-RF.jpg", content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
      ])

    render_upload(photo, "hoof-RF.jpg")
    assert has_element?(view, "#hoof-summary", "lower than usual for a front foot")
    assert has_element?(view, "#hoof-summary", "Broken back")
    assert has_element?(view, "#hoof-correct", "Hoof-pastern axis")

    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    File.rm(Path.join(Application.app_dir(:ranch_phx, "priv/static"), hd(event.photo_urls)))
  end
end
