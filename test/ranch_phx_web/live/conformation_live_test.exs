defmodule RanchPhxWeb.ConformationLiveTest do
  # Not async: the AI runs in LiveView tasks, so the API stub is shared.
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.{Animals, Conformations}
  alias RanchPhx.Training.Coach

  setup :register_and_log_in_user

  setup do
    Req.Test.set_req_test_to_shared()
    {:ok, calls} = Agent.start_link(fn -> [] end)

    {:ok, horse} =
      Animals.create_animal(%{name: "Asher", kind: "horse", birth_date: ~D[2025-05-10]})

    on_exit(fn ->
      File.rm_rf(
        Path.join(Application.app_dir(:ranch_phx, "priv/static"), "uploads/conformation")
      )
    end)

    %{calls: calls, horse: horse}
  end

  defp stub_claude(calls, reply) do
    Req.Test.stub(Coach, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      Agent.update(calls, &(&1 ++ [Jason.decode!(raw)]))
      Req.Test.json(conn, reply)
    end)
  end

  defp text(t),
    do: %{"stop_reason" => "end_turn", "content" => [%{"type" => "text", "text" => t}]}

  defp measure(view, extra \\ %{}) do
    render_hook(
      view,
      "conf_measured",
      Map.merge(
        %{
          "shoulder" => 47.0,
          "hip" => 24.0,
          "uphill" => -2.5,
          "length_ratio" => 1.02,
          "thirds" => [33, 34, 33],
          "neck_ratio" => 1.1,
          "with_original" => true,
          "date" => "2026-10-28",
          "note" => "Seen at the sale",
          "points" => %{"withers" => [%{"x" => 1, "y" => 2}]}
        },
        extra
      )
    )

    for name <- ["marked-body-body.jpg", "original-body-body.jpg"] do
      f =
        file_input(view, "#conf-upload-form", :conf, [
          %{name: name, content: <<0xFF, 0xD8, 0xFF, 0xD9>>, type: "image/jpeg"}
        ])

      render_upload(f, name)
    end
  end

  test "a prospect: save, what it means, AI review, and questions", %{conn: conn, calls: calls} do
    {:ok, view, _} = live(conn, ~p"/conformation")
    view |> form("#who-form", %{who: "prospect", prospect: "Sorrel colt"}) |> render_change()
    measure(view)

    [e] = Conformations.list()
    assert e.name == "Sorrel colt" and is_nil(e.animal_id)
    assert e.original_url =~ "/uploads/conformation/"
    assert has_element?(view, "#conf-summary", "Shoulder 47°: a good slope")
    assert has_element?(view, "#conf-summary", "a little croup-high")
    assert has_element?(view, "#conf-list", "Sorrel colt")
    assert has_element?(view, "#conf-list .cf-tag", "Prospect")
    assert has_element?(view, "#edit-lines")

    stub_claude(calls, text("**What's good**\n- Nice shoulder\n\n**Best suited for**\n- Reining"))
    view |> element("#ask-review") |> render_click()
    render_async(view)
    assert has_element?(view, "#conf-review", "Reining")
    assert Conformations.get(e.id).ai_notes =~ "Best suited for"

    [req] = Agent.get(calls, & &1)
    assert req["system"] =~ "Best suited for"
    [msg] = req["messages"]
    assert Enum.any?(msg["content"], &(&1["type"] == "text" and &1["text"] =~ "shoulder_angle"))

    stub_claude(calls, text("He'd likely suit heeling: good hip angle."))
    view |> form("#ask-form", %{question: "Would he make a heel horse?"}) |> render_submit()
    render_async(view)
    assert has_element?(view, "#conf-chat", "Would he make a heel horse?")
    assert has_element?(view, "#conf-chat", "suit heeling")
    assert [%{"q" => "Would he make a heel horse?"}] = Conformations.get(e.id).ai_chat

    # Redrawing the lines updates the same evaluation and drops the old review.
    measure(view, %{"event_id" => e.id, "with_original" => false, "shoulder" => 52.0})
    [e2] = Conformations.list()
    assert e2.id == e.id and e2.shoulder == 52.0
    assert e2.original_url == e.original_url
    assert is_nil(e2.ai_notes)
  end

  test "one of my horses: from his page, with his age in the read", %{conn: conn, horse: horse} do
    {:ok, view, _} = live(conn, ~p"/conformation?animal=#{horse.id}")
    refute has_element?(view, "#who-form")
    measure(view)
    [e] = Conformations.list(animal_id: horse.id)
    assert e.animal_id == horse.id
    assert has_element?(view, "#conf-summary", "Normal at 1 year old")

    {:ok, show, _} = live(conn, ~p"/animals/#{horse.id}")
    assert has_element?(show, "#conformation-card", "Shoulder 47°")
  end

  test "AI places the dots as fractions of the photo", %{conn: conn, calls: calls} do
    stub_claude(calls, %{
      "stop_reason" => "tool_use",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => "t1",
          "name" => "place_landmarks",
          "input" => %{
            "withers" => %{"x" => 0.35, "y" => 0.3},
            "shoulder" => [%{"x" => 0.37, "y" => 0.35}, %{"x" => 0.28, "y" => 0.5}],
            "hip" => %{"x" => 0.66, "y" => 0.32},
            "buttock" => %{"x" => 0.79, "y" => 0.45},
            "croup" => %{"x" => 0.73, "y" => 0.3},
            "poll" => nil,
            "ground" => [%{"x" => 0.35, "y" => 0.85}, %{"x" => 0.74, "y" => 0.85}],
            "note" => "Head turned a little."
          }
        }
      ]
    })

    {:ok, view, _} = live(conn, ~p"/conformation")
    render_hook(view, "ai_points", %{"image" => Base.encode64("jpeg")})
    render_async(view)

    assert_push_event(view, "ai-points", %{points: points, note: "Head turned a little."})
    assert points["withers"] == %{x: 0.35, y: 0.3}
    assert length(points["shoulder"]) == 2
    assert points["poll"] == nil

    [req] = Agent.get(calls, & &1)
    [tool] = req["tools"]
    assert tool["strict"] == true
    assert "ground" in tool["input_schema"]["required"]
  end

  test "what it means" do
    e = %Conformations.Evaluation{
      shoulder: 58.0,
      hip: 33.0,
      uphill: -6.0,
      length_ratio: 1.2,
      thirds: [25, 45, 30],
      neck_ratio: 0.8
    }

    lines = Conformations.summary(e, 120)
    assert {:check, "Shoulder 58°: upright" <> _} = Enum.at(lines, 0)
    assert {:info, "Hip 33°: steep" <> _} = Enum.at(lines, 1)
    assert {:check, "Croup-high 6%: noticeably" <> _} = Enum.at(lines, 2)
    assert {:info, "Body length is 120%" <> _} = Enum.at(lines, 3)
    assert {:info, "Shoulder / back / hip: 25 / 45 / 30%. The back" <> _} = Enum.at(lines, 4)
    assert {:check, "Neck is 80%" <> _} = Enum.at(lines, 5)
  end
end
