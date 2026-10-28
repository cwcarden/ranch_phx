defmodule RanchPhxWeb.AnimalRecordsTest do
  # Not async: the AI calls run in LiveView tasks, so the API stub is shared.
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.Animals
  alias RanchPhx.Training.Coach

  setup :register_and_log_in_user

  setup do
    Req.Test.set_req_test_to_shared()
    {:ok, animal} = Animals.create_animal(%{name: "Asher", kind: "horse"})
    %{animal: animal}
  end

  defp stub_claude(reply) do
    test = self()

    Req.Test.stub(Coach, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, Jason.decode!(raw)})
      Req.Test.json(conn, reply)
    end)
  end

  defp records_reply(records),
    do: %{
      "model" => "claude-sonnet-5-5",
      "stop_reason" => "tool_use",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => "t1",
          "name" => "add_records",
          "input" => %{"records" => records}
        }
      ]
    }

  defp line(type, title, extra \\ %{}),
    do:
      Map.merge(
        %{
          "record_type" => type,
          "title" => title,
          "date" => nil,
          "next_due_date" => nil,
          "person" => nil,
          "location" => nil,
          "cost" => nil,
          "description" => nil
        },
        extra
      )

  defp open_records(conn, animal) do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    view |> element("button.tab-btn[phx-value-tab=records]") |> render_click()
    view
  end

  defp preset_id(label),
    do: Animals.list_care_presets("horse") |> Enum.find(&(&1.label == label)) |> Map.fetch!(:id)

  test "pick several quick buttons, fill in one visit, and see what's next due",
       %{conn: conn, animal: animal} do
    view = open_records(conn, animal)

    for label <- ["Core EQ Innovator", "Deworming", "Health cert"] do
      view |> element("#quick-#{preset_id(label)}") |> render_click()
    end

    assert has_element?(view, "#quick-bar", "3")
    view |> element("#start-visit") |> render_click()
    assert has_element?(view, "#visit-sheet")

    # Pick the dewormer from the one-tap choices.
    view |> element("#visit-item-1 button", "Panacur PowerPac") |> render_click()

    today = Date.utc_today()
    start = Date.add(today, 7)

    view
    |> form("#visit-form",
      visit: %{
        date: Date.to_iso8601(today),
        person: "Dr. Hall",
        items: %{
          "0" => %{cost: "62.50"},
          "1" => %{date: Date.to_iso8601(start), days: "5"}
        }
      }
    )
    |> render_submit()

    records = Animals.get_animal_with_pedigree!(animal.id).records
    assert length(records) == 3
    vaccine = Enum.find(records, &(&1.record_type == "vaccination"))
    assert vaccine.person == "Dr. Hall"
    assert Decimal.equal?(vaccine.cost, Decimal.new("62.50"))
    assert Date.diff(vaccine.next_due_date, today) in 365..366

    dewormer = Enum.find(records, &(&1.record_type == "deworming"))
    assert dewormer.date == start
    assert dewormer.description =~ "Panacur PowerPac · daily for 5 days"
    # The next deworming counts from when it starts.
    assert Date.diff(dewormer.next_due_date, start) in 181..184

    assert has_element?(view, "#records-due", "Covers EWT / Tetanus, West Nile, Rabies")
    assert has_element?(view, "#records-planned", "Panacur PowerPac")

    # Next time, the dewormer choices offer the product alone, not the saved schedule.
    view |> element("#quick-#{preset_id("Deworming")}") |> render_click()
    view |> element("#start-visit") |> render_click()
    assert has_element?(view, "#visit-item-0 .rx-choice", "Panacur PowerPac")
    refute has_element?(view, "#visit-item-0 .rx-choice", "daily for")
  end

  test "edit the quick buttons", %{conn: conn, animal: animal} do
    view = open_records(conn, animal)
    view |> element("#edit-presets") |> render_click()

    view
    |> form("#preset-new",
      preset: %{
        label: "Vetera Gold",
        record_type: "vaccination",
        title: "Vetera Gold",
        interval_value: "12",
        interval_unit: "months"
      }
    )
    |> render_submit()

    assert Enum.any?(Animals.list_care_presets("horse"), &(&1.label == "Vetera Gold"))
    view |> element("#edit-presets") |> render_click()
    assert has_element?(view, "#records-add button", "Vetera Gold")
  end

  test "what was said opens in the visit form to check, then saves",
       %{conn: conn, animal: animal} do
    stub_claude(
      records_reply([
        line("vaccination", "West Nile vaccine", %{"person" => "Dr. Hall", "cost" => 28.5}),
        line("not_a_type", "Ignored")
      ])
    )

    view = open_records(conn, animal)

    view
    |> form("#rec-voice-form", spoken: "Gave West Nile today, Dr Hall, 28.50")
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#visit-sheet")
    assert has_element?(view, "#visit-item-0")
    refute has_element?(view, "#visit-item-1")

    view |> form("#visit-form") |> render_submit()
    [record] = Animals.get_animal_with_pedigree!(animal.id).records
    assert record.title == "West Nile vaccine"
    assert record.person == "Dr. Hall"
    # No date was said, so it gets the usual interval from the Core EQ Innovator button.
    assert Date.diff(record.next_due_date, Date.utc_today()) in 365..366
  end

  test "a scanned invoice becomes records and the paperwork is saved",
       %{conn: conn, animal: animal} do
    stub_claude(
      records_reply([
        line("vaccination", "Core EQ Innovator (EWT, West Nile, Rabies)", %{
          "cost" => 62.5,
          "date" => "2026-10-24",
          "location" => "Canyon Vet"
        }),
        line("deworming", "Deworming", %{
          "description" => "Ivermectin",
          "cost" => 18.0,
          "date" => "2026-10-24"
        }),
        line("health_cert", "Health certificate exam", %{"cost" => 55.0, "date" => "2026-10-24"})
      ])
    )

    view = open_records(conn, animal)

    scan =
      file_input(view, "#scan-form", :scan, [
        %{name: "invoice.jpg", content: "fake jpeg bytes", type: "image/jpeg"}
      ])

    render_upload(scan, "invoice.jpg")
    render_async(view)

    assert_received {:request, req}
    [%{"content" => [_intro, %{"type" => "image"}, _]}] = req["messages"]
    # No forced tool_choice: the model in use rejects it.
    refute Map.has_key?(req, "tool_choice")
    assert has_element?(view, "#visit-sheet", "scanned paperwork")

    view |> form("#visit-form") |> render_submit()
    animal = Animals.get_animal_with_pedigree!(animal.id)
    assert length(animal.records) == 3
    assert Enum.all?(animal.records, &(&1.location == "Canyon Vet"))
    assert [%{doc_type: "Health Certificate"}] = animal.documents
  end

  test "summarizes the records", %{conn: conn, animal: animal} do
    {:ok, _} =
      Animals.create_record(%{
        "animal_id" => animal.id,
        "record_type" => "coggins",
        "title" => "Coggins test",
        "date" => "2026-03-10"
      })

    stub_claude(%{
      "model" => "claude-sonnet-5-5",
      "stop_reason" => "end_turn",
      "content" => [%{"type" => "text", "text" => "Coggins is current.\n\n- Nothing else due"}]
    })

    view = open_records(conn, animal)
    view |> element("#summarize-records") |> render_click()
    html = render_async(view)
    assert html =~ "Coggins is current."
    assert html =~ "<li>"
  end

  test "a reply in words instead of records says nothing was found",
       %{conn: conn, animal: animal} do
    stub_claude(%{
      "model" => "claude-sonnet-5-5",
      "stop_reason" => "end_turn",
      "content" => [%{"type" => "text", "text" => "I don't see any vet items here."}]
    })

    view = open_records(conn, animal)

    scan =
      file_input(view, "#scan-form", :scan, [%{name: "cat.jpg", content: "x", type: "image/jpeg"}])

    render_upload(scan, "cat.jpg")
    html = render_async(view)
    assert html =~ "find any records"
    refute has_element?(view, "#visit-sheet")
  end

  test "log a weight and see the gain on the Overview and the animal card",
       %{conn: conn, animal: animal} do
    {:ok, _} =
      Animals.create_event(%{
        "animal_id" => animal.id,
        "event_type" => "weight",
        "title" => "700 lb",
        "event_date" => Date.add(Date.utc_today(), -30)
      })

    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    view |> element("#log-weight") |> render_click()

    view
    |> form("#measure-form",
      measure: %{value: "736", method: "tape", date: Date.to_iso8601(Date.utc_today())}
    )
    |> render_submit()

    assert has_element?(view, "#growth-weight", "736 lb")
    assert has_element?(view, "#growth-weight", "+1.2 lb")

    {:ok, list, _} = live(conn, ~p"/")
    assert has_element?(list, ".card-insights", "736 lb")
    assert has_element?(list, ".card-insights", "+1.2 lb/day")
  end

  test "weight history from the card link: compare two weigh-ins; report has the chart",
       %{conn: conn, animal: animal} do
    for {days, lbs} <- [{80, 640}, {40, 690}, {0, 735}] do
      {:ok, _} =
        Animals.create_event(%{
          "animal_id" => animal.id,
          "event_type" => "weight",
          "title" => "#{lbs} lb",
          "event_date" => Date.add(Date.utc_today(), -days)
        })
    end

    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}?data=weight")
    # Opens comparing the first and latest.
    assert has_element?(view, "#data-compare", "+95 lb")
    assert has_element?(view, "#data-compare", "80 days")

    view |> element("#data-rows button[phx-value-i='1']") |> render_click()
    assert has_element?(view, "#data-compare", "second entry")
    view |> element("#data-rows button[phx-value-i='2']") |> render_click()
    assert has_element?(view, "#data-compare", "+45 lb")
    assert has_element?(view, "#data-compare", "+1.1 lb/day")

    html = conn |> get(~p"/animals/#{animal.id}/report?weight=1") |> html_response(200)
    assert html =~ "Weight"
    assert html =~ "polyline"
    assert html =~ "Save / Share PDF"
    # A page of its own: not wrapped in the app's page.
    assert length(String.split(html, "<html")) == 2
  end

  test "log heights in hands, see growth on the card, chart, list and report",
       %{conn: conn, animal: animal} do
    {:ok, _} =
      Animals.create_event(%{
        "animal_id" => animal.id,
        "event_type" => "height",
        "title" => "13.3 hh",
        "metadata" => %{"inches" => 55.0},
        "event_date" => Date.add(Date.utc_today(), -91)
      })

    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    view |> element("#log-height") |> render_click()
    assert has_element?(view, "#measure-sheet", "Log height")

    view
    |> form("#measure-form",
      measure: %{value: "14.2", method: "stick", date: Date.to_iso8601(Date.utc_today())}
    )
    |> render_submit()

    assert has_element?(view, "#growth-height", "14.2 hh")
    assert has_element?(view, "#growth-height", "+1.0 in/mo")

    # Tap the height tile: the data view opens on Height, comparing first and latest.
    view |> element("#growth-height") |> render_click()
    assert has_element?(view, "#tab-height[aria-selected='true']")
    assert has_element?(view, "#data-compare", "+3.0 in")
    assert has_element?(view, "#data-compare", "91 days")

    # Switch tabs without closing.
    view |> element("#tab-weight") |> render_click()
    assert has_element?(view, "#tab-weight[aria-selected='true']")

    {:ok, list, _} = live(conn, ~p"/")
    assert has_element?(list, ".ci-row.ht", "14.2 hh")

    html = conn |> get(~p"/animals/#{animal.id}/report?weight=1") |> html_response(200)
    assert html =~ "Height"
    assert html =~ "14.2 hh"
  end

  test "decimal hands and earlier dates", %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    view |> element("#log-height") |> render_click()

    view |> form("#measure-form", measure: %{value: "13.375"}) |> render_change()
    assert has_element?(view, "#height-read", "13.1½ hh (53.5 inches)")

    earlier = Date.add(Date.utc_today(), -40)

    view
    |> form("#measure-form", measure: %{value: "13.375", date: Date.to_iso8601(earlier)})
    |> render_submit()

    assert has_element?(view, "#growth-height", "13.1½ hh")
    [event] = Animals.get_animal_with_pedigree!(animal.id).timeline_events
    assert event.event_date == earlier
    assert event.metadata["inches"] == 53.5
  end

  test "an impossible height is refused", %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    view |> element("#log-height") |> render_click()

    html =
      view
      |> form("#measure-form", measure: %{value: "abc", date: Date.to_iso8601(Date.utc_today())})
      |> render_submit()

    assert html =~ "rx-err"
  end

  test "Papers shows the newest Coggins and health certificate, matched by type name",
       %{conn: conn, animal: animal} do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    refute has_element?(view, "#show-papers")

    for {type, url, date} <- [
          {"Coggins", "/uploads/old.pdf", ~D[2025-03-01]},
          {"Coggins", "/uploads/new.pdf", ~D[2026-03-10]},
          {"Health Certificate", "/uploads/cvi.png", ~D[2026-10-24]},
          {"Bill of Sale", "/uploads/bos.pdf", ~D[2025-07-15]}
        ] do
      {:ok, _} =
        Animals.create_document(%{
          "animal_id" => animal.id,
          "title" => type,
          "doc_type" => type,
          "file_url" => url,
          "doc_date" => date
        })
    end

    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    assert has_element?(view, "#show-papers")

    papers = RanchPhxWeb.AnimalLive.Show.papers(Animals.get_animal_with_pedigree!(animal.id))

    assert Enum.map(papers, &{&1.type, &1.url}) == [
             {"coggins", "/uploads/new.pdf"},
             {"health_cert", "/uploads/cvi.png"}
           ]
  end
end
