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

  test "photo now, lines later; then edit the lines without deleting",
       %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")
    view |> element("#view-sole") |> render_click()
    view |> element("#pick-RH") |> render_click()

    # On the phone: just the photo.
    later =
      file_input(view, "#hoof-later-form", :hoof_later, [
        %{name: "IMG_1234.jpg", content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
      ])

    render_upload(later, "IMG_1234.jpg")
    [pending] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert pending.metadata["status"] == "pending"
    assert has_element?(view, "#todo-#{pending.id}", "Right hind")
    assert has_element?(view, "#draw-#{pending.id}")
    refute has_element?(view, "#hoof-history .hf-row")

    # Later, on the iPad: lines drawn on that photo update the same entry.
    measure = fn date ->
      render_hook(view, "hoof_measured", %{
        "view" => "sole",
        "event_id" => pending.id,
        "with_original" => false,
        "foot" => "RH",
        "toe_share" => 52.0,
        "sides" => 51.0,
        "heels" => 1.0,
        "frog" => nil,
        "area" => 50.5,
        "ratio" => 0.9,
        "date" => date,
        "points" => %{"toe" => [%{"x" => 10, "y" => 20}]}
      })

      marked =
        file_input(view, "#hoof-upload-form", :hoof, [
          %{name: "marked-RH-sole.jpg", content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
        ])

      render_upload(marked, "marked-RH-sole.jpg")
    end

    measure.("2026-10-20")
    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert event.id == pending.id
    assert event.metadata["status"] == nil
    assert event.metadata["original"] == pending.metadata["original"]
    assert event.metadata["area"] == 50.5
    refute has_element?(view, "#hoof-to-measure")
    assert has_element?(view, "#hoof-summary", "Sole area 50.5/49.5")
    assert has_element?(view, "#edit-lines")
    first_marked = hd(event.photo_urls)

    # Edit lines: same entry again, the old marked-up photo is replaced, the clean one kept.
    measure.("2026-10-21")
    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert event.id == pending.id
    assert event.event_date == ~D[2026-10-21]
    refute hd(event.photo_urls) == first_marked
    static = Application.app_dir(:ranch_phx, "priv/static")
    refute File.exists?(Path.join(static, first_marked))
    assert File.exists?(Path.join(static, event.metadata["original"]))

    for u <- [hd(event.photo_urls), event.metadata["original"]], do: File.rm(Path.join(static, u))
  end

  test "a new photo keeps its clean original next to the marked-up one",
       %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}/hooves")

    render_hook(view, "hoof_measured", %{
      "foot" => "LF",
      "toe" => 52.0,
      "pastern" => 51.0,
      "with_original" => true,
      "date" => Date.to_iso8601(Date.utc_today()),
      "points" => %{}
    })

    for name <- ["marked-LF-side.jpg", "original-LF-side.jpg"] do
      f =
        file_input(view, "#hoof-upload-form", :hoof, [
          %{name: name, content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
        ])

      render_upload(f, name)
    end

    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert event.metadata["original"] =~ "/hooves/"
    refute event.metadata["original"] == hd(event.photo_urls)
    assert has_element?(view, "#edit-lines")
    static = Application.app_dir(:ranch_phx, "priv/static")
    for u <- [hd(event.photo_urls), event.metadata["original"]], do: File.rm(Path.join(static, u))
  end
end
