defmodule RanchPhx.RanchAsk do
  @moduledoc """
  Answers a question asked out loud through the "Ranch ask" Siri Shortcut ("What were
  yesterday's training notes for Asher?", "When is his Coggins due?"), from what the
  app actually has: records, care due dates, training sessions, handwritten notes and
  the latest weights and hoof angles. It also coaches: "he keeps pulling his left hind
  away, what should I try?" gets practical suggestions grounded in what's logged.
  Follow-ups within ten minutes keep the thread (see `RanchAsk.Memory`), and questions
  about a horse with a training book are saved to its Ask the TrAIner history.
  The answer is short and plain, for Siri to read.
  """
  import Ecto.Query
  alias RanchPhx.{Animals, LocalTime, Notes, Repo, Training, VoiceNotes}
  alias RanchPhx.Animals.{Animal, CareSchedule}
  alias RanchPhx.Training.{Coach, CoachMessage, Issue}
  alias RanchPhx.RanchAsk.Memory

  @system """
  You're the ranch's horse and livestock helper, asked out loud through Siri on a phone
  (often at the barn, hands full). Siri reads your answer aloud, so:

  - Answer in two to four short, plain sentences. No lists, headings, bold, emoji or links.
  - Say dates the way people talk ("yesterday", "last Tuesday", "October 12th").
  - Use the animal's barn name when it has one (it's what the owner calls him).
  - Facts about the animals (what was done, when, how much, what's due) come only from
    the ranch data given. If it isn't there, say so briefly. Never invent records,
    numbers or dates.
  - Problems and "what should I try" questions: give practical, specific suggestions the
    way an experienced horseman would, fitted to the animal's age, training stage and
    what's been logged (recent sessions, what he's working on, how he's been). Lead with
    the one thing to try first. Safety first with young horses.
  - Anything that sounds like a health problem (lameness, colic signs, not eating, a
    wound, swelling, fever, choke, trouble breathing): say plainly to call the vet, and
    give only safe first steps while waiting. Don't diagnose.
  - Follow-up questions continue the earlier conversation; keep the same animal unless a
    different one is named.
  """

  @doc "Answers `question` for `user_id` (who asked; keeps follow-ups together). `{:ok, text}` or `{:error, reason}`."
  def answer(question, today \\ LocalTime.today(), user_id \\ nil) do
    question = question |> to_string() |> String.trim()

    cond do
      question == "" -> {:error, :empty}
      not Coach.configured?() -> {:error, :no_api_key}
      true -> ask(question, today, user_id)
    end
  end

  def error_message(:empty), do: "I didn't catch a question."
  def error_message(:no_api_key), do: "The AI isn't set up on the ranch app yet."
  def error_message(_), do: "The ranch app couldn't get an answer just now. Try again in a minute."

  defp ask(question, today, user_id) do
    convo = Memory.recall(user_id)
    {ctx, detail} = context_for(question, today, convo.animal_ids)

    history =
      Enum.flat_map(convo.turns, fn {q, a} ->
        [%{role: "user", content: q}, %{role: "assistant", content: a}]
      end)

    body = %{
      model: Coach.model_name(),
      max_tokens: 500,
      system: @system,
      messages:
        history ++
          [
            %{
              role: "user",
              content:
                "Today is #{Calendar.strftime(today, "%A, %B %-d, %Y")}.\n\nRanch data (JSON):\n" <>
                  Jason.encode!(ctx) <>
                  "\n\n" <> if(history == [], do: "Question: ", else: "Follow-up: ") <> question
            }
          ]
    }

    with {:ok, resp} <- Coach.api_request(body),
         [_ | _] = blocks <- resp["content"] |> List.wrap() |> Enum.filter(&(&1["type"] == "text")) do
      text = blocks |> Enum.map_join(" ", & &1["text"]) |> String.trim()
      threads = save_to_trainer(detail, question, text, convo.threads, resp["model"])
      Memory.remember(user_id, question, text, Enum.map(detail, & &1.id), threads)
      {:ok, text}
    else
      [] -> {:error, :empty_answer}
      other -> other
    end
  end

  # One horse in the question with an active training book: the question and answer go
  # into its Ask the TrAIner history, follow-ups in the same conversation.
  defp save_to_trainer([%Animal{id: id}], question, answer, threads, model) do
    case Training.active_book_for_animal(id) do
      nil ->
        %{}

      book ->
        root = threads[book.id]

        case Repo.insert(%CoachMessage{
               book_id: book.id,
               thread_id: root,
               question: question,
               answer: answer,
               checked: ["Asked through Siri"],
               model: model || Coach.model_name()
             }) do
          {:ok, msg} -> %{book.id => root || msg.id}
          _ -> %{}
        end
    end
  rescue
    _ -> %{}
  end

  defp save_to_trainer(_, _, _, _, _), do: %{}

  @doc false
  def context(question, today), do: question |> context_for(today, []) |> elem(0)

  # Every animal in brief; full detail for the ones the question names, else the ones
  # the conversation was just about, else the active ones (a small ranch fits).
  defp context_for(question, today, recent_ids) do
    animals = Repo.all(from a in Animal, where: a.owned == true, order_by: a.name)

    detail =
      case VoiceNotes.match_animals(question, animals) do
        [] ->
          case Enum.filter(animals, &(&1.id in recent_ids)) do
            [] -> animals |> Enum.filter(&(&1.status == "active")) |> Enum.take(6)
            recent -> recent
          end

        found ->
          found
      end

    {%{animals: Enum.map(animals, &brief/1), details: Enum.map(detail, &detail(&1, today))}, detail}
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
