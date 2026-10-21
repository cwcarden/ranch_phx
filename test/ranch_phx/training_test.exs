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

  test "re-sending a session with the same client_id updates it instead of duplicating" do
    book = book(horse())
    client_id = Ecto.UUID.generate()

    attrs = %{
      "book_id" => book.id,
      "client_id" => client_id,
      "date" => "2026-10-21",
      "session_type" => "flag",
      "minutes" => "15"
    }

    {:ok, _} = Training.save_session(attrs)

    {:ok, _} =
      Training.save_session(Map.merge(attrs, %{"minutes" => "20", "tags" => ["sticky_left"]}))

    assert [%{minutes: 20, tags: ["sticky_left"]}] = Training.list_sessions(book.id)
    assert Training.week_summary(book.id, ~D[2026-10-21]) == %{sessions: 1, minutes: 20}
  end

  test "guardrail warnings for long sessions, busy weeks and early work" do
    book = book(horse())
    stage = Training.progress(book, ~D[2026-10-21]).stage

    assert Training.guardrail_warnings(stage, %{minutes: 15, session_type: "flag"}, %{sessions: 0}) ==
             []

    warnings =
      Training.guardrail_warnings(stage, %{minutes: 45, session_type: "riding"}, %{sessions: 4})

    assert length(warnings) == 3
    assert Enum.any?(warnings, &(&1 =~ "Riding isn't part of this stage"))
  end
end
