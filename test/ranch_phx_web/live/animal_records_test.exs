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
    Req.Test.stub(Coach, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(self(), {:request, Jason.decode!(raw)})
      Req.Test.json(conn, reply)
    end)
  end

  defp open_records(conn, animal) do
    {:ok, view, _} = live(conn, ~p"/animals/#{animal.id}")
    view |> element("button.tab-btn[phx-value-tab=records]") |> render_click()
    view
  end

  test "a quick-add button fills in the form, and saving shows it as coming due",
       %{conn: conn, animal: animal} do
    view = open_records(conn, animal)
    view |> element("#quick-deworming") |> render_click()
    html = render(view)
    assert html =~ ~s(value="Deworming")

    view
    |> form("form[phx-submit=save_record]",
      record: %{
        record_type: "deworming",
        title: "Deworming",
        date: Date.to_iso8601(Date.add(Date.utc_today(), -85)),
        next_due_date: Date.to_iso8601(Date.add(Date.utc_today(), 5))
      }
    )
    |> render_submit()

    assert has_element?(view, "#records-due", "Deworming")
    assert has_element?(view, "#records-due", "In 5 days")
  end

  test "drafts records from what was said, then adds the ones kept",
       %{conn: conn, animal: animal} do
    stub_claude(%{
      "model" => "claude-sonnet-5-5",
      "stop_reason" => "tool_use",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => "t1",
          "name" => "add_records",
          "input" => %{
            "records" => [
              %{
                "record_type" => "vaccination",
                "title" => "West Nile vaccine",
                "date" => nil,
                "next_due_date" => nil,
                "person" => "Dr. Hall",
                "location" => nil,
                "cost" => 28.5,
                "description" => nil
              },
              %{
                "record_type" => "deworming",
                "title" => "Deworming – Quest Plus",
                "date" => nil,
                "next_due_date" => nil,
                "person" => nil,
                "location" => nil,
                "cost" => nil,
                "description" => "Quest Plus gel"
              },
              %{
                "record_type" => "not_a_type",
                "title" => "Ignored",
                "date" => nil,
                "next_due_date" => nil,
                "person" => nil,
                "location" => nil,
                "cost" => nil,
                "description" => nil
              }
            ]
          }
        }
      ]
    })

    view = open_records(conn, animal)

    view
    |> form("#rec-voice-form", spoken: "Gave West Nile today, Dr Hall, and dewormed with Quest")
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#rec-drafts", "West Nile vaccine")
    assert has_element?(view, "#rec-drafts", "usual interval")
    refute has_element?(view, "#rec-drafts", "Ignored")

    # Leave the deworming out, add the West Nile shot.
    view |> element("#rec-drafts input[phx-value-i='1']") |> render_click()
    view |> element("#save-drafts") |> render_click()

    [record] = Animals.get_animal_with_pedigree!(animal.id).records
    assert record.title == "West Nile vaccine"
    assert record.person == "Dr. Hall"
    assert record.category == "health"

    # No date was said, so it gets the usual 12 months.
    assert Date.diff(record.next_due_date, Date.utc_today()) in 365..366
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
end
