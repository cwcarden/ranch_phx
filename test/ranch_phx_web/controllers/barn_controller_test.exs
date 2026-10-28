defmodule RanchPhxWeb.BarnControllerTest do
  use RanchPhxWeb.ConnCase, async: true
  alias RanchPhx.{Animals, Repo, Training}

  setup :register_and_log_in_user

  setup do
    {:ok, horse} =
      Animals.create_animal(%{name: "Asher", kind: "horse", birth_date: ~D[2025-05-10]})

    {:ok, rec} =
      Animals.create_record(%{
        "animal_id" => horse.id,
        "category" => "health",
        "record_type" => "deworming",
        "title" => "Bute",
        "description" => "Bute · daily for 3 days",
        "date" => RanchPhx.LocalTime.today()
      })

    %{horse: horse, rec: rec}
  end

  test "snapshot: what Barn mode keeps on the device", %{conn: conn, horse: horse} do
    body = conn |> get(~p"/api/barn/snapshot") |> json_response(200)
    assert body["can_edit"]
    a = Enum.find(body["snapshot"]["animals"], &(&1["id"] == horse.id))
    assert a["name"] == "Asher"
    assert [%{"title" => "Bute", "total" => 3}] = a["courses"]
    assert Enum.any?(a["records"], &(&1["title"] == "Bute"))
    assert body["snapshot"]["record_types"]["health"] != []
  end

  test "sync: records, notes, doses; each once however often it's sent",
       %{conn: conn, horse: horse, rec: rec} do
    today = Date.to_iso8601(RanchPhx.LocalTime.today())

    ops = [
      %{
        "client_id" => "a1",
        "kind" => "record",
        "animal_id" => horse.id,
        "category" => "health",
        "type" => "",
        "title" => "Temp 100.2",
        "date" => today,
        "notes" => "At the barn"
      },
      %{
        "client_id" => "a2",
        "kind" => "note",
        "animal_id" => horse.id,
        "text" => "Hay delivered",
        "date" => today
      },
      %{
        "client_id" => "a3",
        "kind" => "dose",
        "animal_id" => horse.id,
        "record_id" => rec.id,
        "date" => today
      },
      %{
        "client_id" => "a4",
        "kind" => "note",
        "animal_id" => horse.id,
        "text" => "Gave Asher Panacur",
        "review" => true
      }
    ]

    for _ <- 1..2 do
      body = conn |> post(~p"/api/barn/sync", %{"ops" => ops}) |> json_response(200)
      assert Enum.all?(body["results"], & &1["ok"])
    end

    a = Animals.get_animal_with_pedigree!(horse.id)

    assert [%{notes: "At the barn", record_type: type}] =
             Enum.filter(a.records, &(&1.title == "Temp 100.2"))

    assert type
    assert [_] = Enum.filter(a.timeline_events, &(&1.title == "Hay delivered"))
    assert RanchPhx.LocalTime.today() in Repo.reload(rec).course_done
    assert RanchPhx.VoiceNotes.count_pending() >= 1
  end

  test "sync: a training session", %{conn: conn, horse: horse} do
    [program | _] = Training.list_programs()

    {:ok, _} =
      Training.start_book(%{"animal_id" => horse.id}, %{
        "program_id" => program.id,
        "started_on" => "2026-10-01"
      })

    [act | _] = Training.list_activities()

    op = %{
      "client_id" => Ecto.UUID.generate(),
      "kind" => "training",
      "animal_id" => horse.id,
      "activity_ids" => [act.id],
      "minutes" => 20,
      "date" => "2026-10-28",
      "note" => "Round pen"
    }

    body = conn |> post(~p"/api/barn/sync", %{"ops" => [op]}) |> json_response(200)
    assert [%{"ok" => true}] = body["results"]
    book = Training.active_book_for_animal(horse.id)
    assert [%{minutes: 20, note: "Round pen"}] = Training.list_sessions(book.id)
  end

  test "a hoof photo taken offline lands in To measure", %{conn: conn, horse: horse} do
    path = Path.join(System.tmp_dir!(), "barn-test.jpg")
    File.write!(path, <<0xFF, 0xD8, 0xFF, 0xD9>>)
    upload = %Plug.Upload{path: path, filename: "barn.jpg", content_type: "image/jpeg"}

    for _ <- 1..2 do
      conn
      |> post(~p"/api/barn/photo", %{
        "client_id" => "p1",
        "animal_id" => horse.id,
        "foot" => "LF",
        "view" => "sole",
        "file" => upload
      })
      |> json_response(200)
    end

    [pending] =
      RanchPhx.Animals.Hooves.to_measure(
        Animals.get_animal_with_pedigree!(horse.id).timeline_events
      )

    assert pending.foot == "LF" and pending.view == "sole"
    File.rm(Path.join(Application.app_dir(:ranch_phx, "priv/static"), pending.photo))
  end

  test "writes refused from another site", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://evil.example")
      |> post(~p"/api/barn/sync", %{"ops" => []})

    assert json_response(conn, 403)
  end
end
