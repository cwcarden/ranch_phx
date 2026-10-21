defmodule RanchPhx.TrainingTest do
  use RanchPhx.DataCase, async: true

  alias RanchPhx.{Animals, Training}

  defp horse(attrs \\ %{}) do
    {:ok, animal} =
      Animals.create_animal(
        Map.merge(%{name: "Asher", kind: "horse", birth_date: ~D[2025-05-10]}, attrs)
      )

    animal
  end

  defp book(animal) do
    [program | _] = Training.list_programs()

    {:ok, book} =
      Training.start_book(%{"animal_id" => animal.id}, %{
        "program_id" => program.id,
        "started_on" => ~D[2026-10-21]
      })

    Training.get_book!(book.id)
  end

  test "age_in_months counts whole months from foaling" do
    assert Training.age_in_months(~D[2025-05-10], ~D[2026-10-09]) == 16
    assert Training.age_in_months(~D[2025-05-10], ~D[2026-10-10]) == 17
    assert Training.age_in_months(~D[2025-05-10], ~D[2025-05-01]) == 0
  end

  test "stage follows age, and a pinned stage wins until cleared" do
    book = book(horse())

    assert %{
             stage: %{name: "Yearling groundwork & desensitizing"},
             next: %{name: "Saddling & ground driving"},
             months_to_next: 3
           } =
             Training.progress(book, ~D[2026-10-21])

    assert Training.progress(book, ~D[2027-05-10]).stage.name == "Backing & first rides"

    next = Training.progress(book, ~D[2026-10-21]).next
    {:ok, _} = Training.set_stage_override(book, next.id)
    pinned = Training.get_book!(book.id)

    assert %{stage: %{name: "Saddling & ground driving"}, overridden?: true} =
             Training.progress(pinned, ~D[2026-10-21])

    {:ok, _} = Training.set_stage_override(pinned, nil)
    refute Training.progress(Training.get_book!(book.id), ~D[2026-10-21]).overridden?
  end

  test "an older horse starts in a later stage" do
    book = book(horse(%{name: "Rusty", birth_date: ~D[2022-04-01]}))
    assert Training.progress(book, ~D[2026-10-21]).stage.name == "Show prep"
  end

  test "only one open book per horse" do
    animal = horse()
    book(animal)
    [program | _] = Training.list_programs()

    assert {:error, :book, changeset} =
             Training.start_book(%{"animal_id" => animal.id}, %{
               "program_id" => program.id,
               "started_on" => ~D[2026-10-21]
             })

    assert "already has an open training book" in errors_on(changeset).horse_id
    assert Training.ranch_horses_without_book() == []
  end

  test "a ranch horse's profile is copied from the ranch record" do
    book = book(horse(%{owner: "Gimel Ranch"}))
    assert %{name: "Asher", foaled_on: ~D[2025-05-10], owner: "Gimel Ranch"} = book.horse
    assert Training.active_book_for_animal(book.horse.animal_id).id == book.id
  end

  test "an outside horse gets its own profile" do
    [program | _] = Training.list_programs()

    {:ok, book} =
      Training.start_book(
        %{"name" => "Smokey", "foaled_on" => "2024-08-01", "owner" => "J. Smith"},
        %{"program_id" => program.id, "started_on" => "2026-10-21"}
      )

    book = Training.get_book!(book.id)
    assert %{name: "Smokey", animal_id: nil, owner: "J. Smith"} = book.horse
    assert Training.progress(book, ~D[2026-10-21]).stage.name == "Backing & first rides"

    assert {:error, :horse, changeset} =
             Training.start_book(%{"name" => " "}, %{
               "program_id" => program.id,
               "started_on" => "2026-10-21"
             })

    assert errors_on(changeset).name
  end

  defp act(slug), do: Enum.find(Training.list_activities(), &(&1.slug == slug))

  test "a session holds several activities, and re-sending updates instead of duplicating" do
    book = book(horse())
    client_id = Ecto.UUID.generate()

    attrs = %{
      "book_id" => book.id,
      "client_id" => client_id,
      "date" => "2026-10-20",
      "minutes" => "30",
      "activities" => [
        %{"activity_id" => act("groundwork").id},
        %{"activity_id" => act("feet").id, "result" => "trouble", "side" => "left"},
        %{"activity_id" => act("longeing").id, "result" => "good"}
      ]
    }

    {:ok, _} = Training.save_session(attrs)

    {:ok, _} =
      Training.save_session(
        Map.merge(attrs, %{
          "tags" => ["sticky_left"],
          "activities" => [
            %{"activity_id" => act("feet").id, "result" => "mixed", "side" => "left"}
          ]
        })
      )

    assert [%{minutes: 30, tags: ["sticky_left"], activities: [feet]}] =
             Training.list_sessions(book.id)

    assert %{result: "mixed", side: "left", activity: %{slug: "feet"}} = feet
    assert Training.week_summary(book.id, ~D[2026-10-21]) == %{sessions: 1, minutes: 30}
  end

  test "a session needs at least one valid activity" do
    book = book(horse())
    base = %{"book_id" => book.id, "client_id" => Ecto.UUID.generate(), "date" => "2026-10-21"}

    assert {:error, cs} = Training.save_session(Map.put(base, "activities", []))
    assert errors_on(cs).activities

    bad = [%{"activity_id" => act("feet").id, "side" => "upside down"}]
    assert {:error, _} = Training.save_session(Map.put(base, "activities", bad))
  end

  test "guardrail warnings for long sessions, busy weeks and early work" do
    book = book(horse())
    stage = Training.progress(book, ~D[2026-10-21]).stage
    gated = Training.gated_activities(book.program)
    {:ok, clippers} = Training.create_activity("Clippers")

    assert Training.guardrail_warnings(
             stage,
             %{minutes: 15, activities: [act("flag"), act("longeing"), clippers]},
             %{sessions: 0},
             gated
           ) == []

    warnings =
      Training.guardrail_warnings(
        stage,
        %{minutes: 45, activities: [act("riding")]},
        %{sessions: 4},
        gated
      )

    assert length(warnings) == 3
    assert Enum.any?(warnings, &(&1 =~ "Riding isn't part of this stage"))
  end

  test "activity and tag lists can be added to, renamed, hidden and reordered" do
    {:ok, a} = Training.create_activity("Clippers")
    {:ok, a2} = Training.create_activity("Clippers")
    assert {a.slug, a2.slug} == {"clippers", "clippers_2"}

    {:ok, _} = Training.update_item(a, %{"name" => "Clipping", "archived" => true})
    refute Enum.any?(Training.list_activities(), &(&1.id == a.id))

    assert Enum.find(Training.list_activities(archived: true), &(&1.id == a.id)).name ==
             "Clipping"

    {:ok, tag} = Training.create_tag("Lazy", "problem")
    [first | _] = Training.list_tags()
    :ok = Training.move_item(tag, -1)
    tags = Training.list_tags()
    assert Enum.find_index(tags, &(&1.id == tag.id)) == length(tags) - 2
    assert hd(tags).id == first.id
  end

  test "goals: add, edit, finish, and the next dated goal drives the countdown" do
    book = book(horse())

    {:ok, show} =
      Training.create_goal(book, %{"title" => "Stallion Stakes", "target_date" => "2029-04-15"})

    {:ok, trailer} =
      Training.create_goal(book, %{"title" => "Loads alone", "target_date" => "2027-03-01"})

    {:ok, _} = Training.create_goal(book, %{"title" => "Stands tied 20 min"})

    progress = Training.progress(Training.get_book!(book.id), ~D[2026-10-21])
    assert progress.next_goal.id == trailer.id
    assert progress.days_to_goal == Date.diff(~D[2027-03-01], ~D[2026-10-21])

    {:ok, _} = Training.set_goal_status(trailer, "done", ~D[2026-10-21])
    {:ok, _} = Training.update_goal(show, %{"title" => "NRCHA Stallion Stakes"})

    book = Training.get_book!(book.id)
    assert Training.progress(book, ~D[2026-10-21]).next_goal.title == "NRCHA Stallion Stakes"

    assert %{status: "done", done_on: ~D[2026-10-21]} =
             Enum.find(book.goals, &(&1.id == trailer.id))
  end

  test "starting a book with a goal creates it" do
    [program | _] = Training.list_programs()

    {:ok, book} =
      Training.start_book(%{"name" => "Smokey"}, %{
        "program_id" => program.id,
        "started_on" => "2026-10-21",
        "goal" => "Ranch versatility",
        "goal_date" => "2027-06-01"
      })

    assert [%{title: "Ranch versatility", target_date: ~D[2027-06-01]}] =
             Training.get_book!(book.id).goals
  end

  test "routines are saved per horse" do
    book = book(horse())

    {:ok, r} =
      Training.create_routine(%{
        "horse_id" => book.horse_id,
        "name" => "Usual groundwork",
        "activity_ids" => [act("groundwork").id, act("feet").id],
        "minutes" => "30"
      })

    assert [%{name: "Usual groundwork", minutes: 30}] = Training.list_routines(book.horse_id)

    assert {:error, _} =
             Training.create_routine(%{"horse_id" => book.horse_id, "name" => "Empty"})

    Training.delete_routine(book.horse_id, r.id)
    assert Training.list_routines(book.horse_id) == []
  end
end
