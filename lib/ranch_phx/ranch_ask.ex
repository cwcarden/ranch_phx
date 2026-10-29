defmodule RanchPhx.RanchAsk do
  @moduledoc """
  Answers a question asked out loud through the "Ranch ask" Siri Shortcut ("What were
  yesterday's training notes for Asher?", "When is his Coggins due?"), from what the
  app actually has: records, care due dates, training sessions, handwritten notes and
  the latest weights and hoof angles. The answer is short and plain, for Siri to read.
  """
  import Ecto.Query
  alias RanchPhx.{Animals, LocalTime, Notes, Repo, Training, VoiceNotes}
  alias RanchPhx.Animals.{Animal, CareSchedule}
  alias RanchPhx.Training.{Coach, Issue}

  @system """
  You answer questions about a small ranch's animals, asked out loud to Siri on a phone.
  Siri reads your answer aloud, so:

  - Answer in one to three short, plain sentences. No lists, headings, bold, emoji or links.
  - Say dates the way people talk ("yesterday", "last Tuesday", "October 12th").
  - Use the animal's barn name when it has one (it's what the owner calls him).
  - Only use the ranch data given. If it doesn't have the answer, say so briefly and say
    what it does have that's close, if anything.
  - Never invent records, numbers, dates or advice.
  """

  @doc "Answers `question`. `{:ok, text}` or `{:error, reason}`."
  def answer(question, today \\ LocalTime.today()) do
    question = question |> to_string() |> String.trim()

    cond do
      question == "" -> {:error, :empty}
      not Coach.configured?() -> {:error, :no_api_key}
      true -> ask(question, today)
    end
  end

  def error_message(:empty), do: "I didn't catch a question."
  def error_message(:no_api_key), do: "The AI isn't set up on the ranch app yet."
  def error_message(_), do: "The ranch app couldn't get an answer just now. Try again in a minute."

  defp ask(question, today) do
    body = %{
      model: Coach.model_name(),
      max_tokens: 400,
      system: @system,
      messages: [
        %{
          role: "user",
          content:
            "Today is #{Calendar.strftime(today, "%A, %B %-d, %Y")}.\n\nRanch data (JSON):\n" <>
              Jason.encode!(context(question, today)) <> "\n\nQuestion: " <> question
        }
      ]
    }

    with {:ok, resp} <- Coach.api_request(body) do
      case resp["content"] |> List.wrap() |> Enum.filter(&(&1["type"] == "text")) do
        [] -> {:error, :empty_answer}
        blocks -> {:ok, blocks |> Enum.map_join(" ", & &1["text"]) |> String.trim()}
      end
    end
  end

  @doc false
  # Every animal in brief; full detail for the ones the question names (or, when it
  # names none, the active ones, since a small ranch's whole picture fits).
  def context(question, today) do
    animals = Repo.all(from a in Animal, where: a.owned == true, order_by: a.name)
    named = VoiceNotes.match_animals(question, animals)

    detail =
      case named do
        [] -> animals |> Enum.filter(&(&1.status == "active")) |> Enum.take(6)
        found -> found
      end

    %{
      animals: Enum.map(animals, &brief/1),
      details: Enum.map(detail, &detail(&1, today))
    }
  end

  defp brief(a) do
    compact(%{
      name: a.name,
      barn_name: a.barn_name,
      kind: a.kind,
      sex: a.sex,
      breed: a.breed,
      color: a.color,
      born: iso(a.birth_date),
      status: a.status
    })
  end

  defp detail(%Animal{} = a, today) do
    full = Animals.get_animal_with_pedigree!(a.id)
    records = Enum.take(full.records, 60)

    compact(%{
      animal: a.barn_name || a.name,
      registered_name: a.name,
      registration_number: a.registration_number,
      records:
        Enum.map(records, fn r ->
          compact(%{
            date: iso(r.date),
            type: r.record_type,
            title: r.title,
            next_due: iso(r.next_due_date),
            by: r.person,
            cost: r.cost && Decimal.to_string(r.cost),
            details: CareSchedule.describe(r.description, r.date),
            notes: r.notes
          })
        end),
      care_due:
        full.records
        |> CareSchedule.status(today)
        |> Enum.sort_by(& &1.days)
        |> Enum.take(12)
        |> Enum.map(fn s ->
          %{what: s.record.title, due: iso(s.record.next_due_date), days_from_today: s.days}
        end),
      measurements_and_events:
        full.timeline_events
        |> Enum.sort_by(&{&1.event_date, &1.id}, :desc)
        |> Enum.take(30)
        |> Enum.map(fn e ->
          compact(%{date: iso(e.event_date), type: e.event_type, title: e.title, details: e.description})
        end),
      training: training(a),
      handwritten_notes:
        a.id
        |> Notes.list()
        |> Enum.take(10)
        |> Enum.map(fn n -> compact(%{date: iso(n.date), topic: n.topic, title: n.title, text: n.text}) end)
    })
  end

  defp training(%Animal{id: id}) do
    case Training.active_book_for_animal(id) do
      nil ->
        nil

      book ->
        open =
          Repo.all(from i in Issue, where: i.horse_id == ^book.horse_id and i.status == "open", order_by: i.opened_on)

        %{
          sessions:
            book.id
            |> Training.list_sessions(15)
            |> Enum.map(fn s ->
              compact(%{
                date: iso(s.date),
                minutes: s.minutes,
                how_he_was: s.tags,
                note: s.note,
                activities:
                  Enum.map(s.activities, fn sa ->
                    compact(%{what: sa.activity && sa.activity.name, result: sa.result, side: sa.side, note: sa.note})
                  end),
                working_on:
                  Enum.map(s.issue_marks, fn m ->
                    compact(%{issue: m.issue && m.issue.title, progress: m.progress, note: m.note})
                  end)
              })
            end),
          working_on: Enum.map(open, fn i -> compact(%{issue: i.title, side: i.side, notes: i.notes}) end)
        }
    end
  rescue
    # Training is extra context; a hiccup there shouldn't stop the answer.
    _ -> nil
  end

  defp iso(nil), do: nil
  defp iso(%Date{} = d), do: Date.to_iso8601(d)

  defp compact(map),
    do: map |> Enum.reject(fn {_, v} -> v in [nil, "", []] end) |> Map.new()
end
