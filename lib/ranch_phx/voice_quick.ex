defmodule RanchPhx.VoiceQuick do
  @moduledoc """
  Routine things said to Siri that are saved straight away, without waiting in the
  voice log for review:

    * "Gave Asher his Panacur" checks off today's dose of a running treatment.
    * "Asher weighed 805" (or "805 on the tape") logs his weight for today.

  Anything bigger (a vet visit, a training session, two animals at once) still waits
  to be checked. Each quick save is also kept in the voice log as done, for the record.
  And `brief/2` is the spoken "what's due today" rundown.
  """
  import Ecto.Query
  alias RanchPhx.{Animals, Repo, Training}
  alias RanchPhx.Animals.{Animal, CareSchedule}
  alias RanchPhx.VoiceNotes.VoiceNote

  @gave ~r/\b(gave|given|give|dosed|dose|got (his|her|its)|had (his|her)|did|done|finished|soaked|wrapped|walked|hosed|treated|applied)\b/i

  @doc "Saves `text` straight away when it's routine: `{:ok, message}`, or `:none`."
  def try_quick(user, text, [%Animal{} = animal], today) do
    case check_off(animal, text, today) do
      {:ok, message} ->
        %VoiceNote{}
        |> VoiceNote.changeset(%{text: text, animal_id: animal.id, user_id: user && user.id, status: "done"})
        |> Repo.insert()

        {:ok, message}

      :none ->
        :none
    end
  end

  # No animal named ("Gave the first dose of Panacur"): when exactly one animal has a
  # running treatment that fits what was said, that's the one.
  def try_quick(user, text, [], today) do
    if Regex.match?(@gave, text) do
      fits =
        Repo.all(from a in Animal, where: a.owned == true and a.status == "active")
        |> Enum.filter(fn a ->
          full = Animals.get_animal_with_pedigree!(a.id)
          full.records |> CareSchedule.active_courses(today) |> Enum.any?(&(&1.today_i != nil and course_named?(&1, text)))
        end)

      case fits do
        [one] -> try_quick(user, text, [one], today)
        _ -> :none
      end
    else
      :none
    end
  end

  def try_quick(_user, _text, _animals, _today), do: :none

  @doc """
  Does the routine part for one animal (today's dose, a weight) without touching the
  voice log: `{:ok, message}` or `:none`. Also used when a waiting note is opened.
  """
  def check_off(%Animal{} = animal, text, today) do
    full = Animals.get_animal_with_pedigree!(animal.id)

    with :none <- weight(full, text, today) do
      dose(full, text, today)
    end
  end

  # ── Weight ──

  @weight ~r/\b(?:weigh(?:ed|s|ing)?|weight(?:\s+(?:is|was|of))?|taped(?:\s+at)?)\s+(?:in\s+at\s+|at\s+|about\s+|around\s+)?(\d{3,4})(?:\s*(?:lb|lbs|pounds))?\b/i
  @weight_alt ~r/\b(\d{3,4})\s*(?:lb|lbs|pounds)\b/i

  defp weight(animal, text, today) do
    case Regex.run(@weight, text) || (Regex.match?(~r/\bweigh|\bweight|\btape/i, text) && Regex.run(@weight_alt, text)) do
      [_, n] ->
        lbs = String.to_integer(n)
        t = String.downcase(text)

        method =
          cond do
            String.contains?(t, "tape") -> "tape"
            String.contains?(t, "scale") -> "scale"
            String.contains?(t, ["guess", "estimate", "about", "around"]) -> "estimate"
            true -> nil
          end

        if lbs >= 20 and lbs <= 3000 do
          {:ok, _} =
            Animals.create_event(%{
              "animal_id" => animal.id,
              "event_type" => "weight",
              "title" => "#{lbs} lb#{if method, do: " (#{method})"}",
              "event_date" => today,
              "metadata" => %{"lbs" => lbs, "method" => method, "source" => "siri"}
            })

          {:ok, "Logged #{Animal.display_name(animal)} at #{lbs} pounds."}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # ── Today's dose of a running treatment ──


  defp dose(animal, text, today) do
    courses =
      animal.records
      |> CareSchedule.active_courses(today)
      |> Enum.filter(&(&1.today_i != nil))

    named = Enum.filter(courses, &course_named?(&1, text))

    pick =
      cond do
        not Regex.match?(@gave, text) -> nil
        length(named) == 1 -> hd(named)
        named == [] and length(courses) == 1 and Regex.match?(~r/\b(dose|medicine|meds|treatment|dewormer|wormer)\b/i, text) -> hd(courses)
        true -> nil
      end

    case pick do
      nil ->
        :none

      %{today_given?: true} = c ->
        {:ok, "#{Animal.display_name(animal)}'s #{c.record.title} was already checked off for today, day #{c.today_i + 1} of #{c.total}."}

      c ->
        done = Enum.sort([today | c.record.course_done || []], Date) |> Enum.uniq()
        {:ok, _} = Animals.update_record(c.record, %{course_done: done})
        left = c.total - (c.today_i + 1)

        {:ok,
         "Checked off #{Animal.display_name(animal)}'s #{c.record.title}, day #{c.today_i + 1} of #{c.total}." <>
           cond do
             left == 0 -> " That's the last one."
             left == 1 -> " One more tomorrow."
             true -> ""
           end}
    end
  end

  # Does what was said name this treatment? Product words, allowing for how dictation
  # spells them ("Panacea" for Panacur), or the kind of treatment ("dewormer").
  @doc false
  def course_named?(c, text) do
    said = text |> String.downcase() |> String.split(~r/[^a-z]+/, trim: true)

    words =
      "#{c.record.title} #{c.record.description}"
      |> String.downcase()
      |> String.split(~r/[^a-z]+/, trim: true)
      |> Enum.filter(&(String.length(&1) >= 4))
      |> Enum.reject(&(&1 in ~w(daily days with dose given qty)))

    product? =
      Enum.any?(words, fn w ->
        Enum.any?(said, fn s ->
          s == w or (String.length(s) >= 5 and String.length(w) >= 5 and
                       String.slice(s, 0, 3) == String.slice(w, 0, 3) and String.jaro_distance(s, w) >= 0.8)
        end)
      end)

    kind? =
      case c.record.record_type do
        "deworming" -> Enum.any?(said, &String.starts_with?(&1, ["deworm", "wormer"]))
        _ -> false
      end

    product? or kind?
  end

  # ── The spoken rundown ──

  @doc false
  def brief_request?(text) do
    t = text |> to_string() |> String.downcase() |> String.trim()
    words = length(String.split(t))

    t in ["today", "ranch today", "barn today", "rundown", "brief", "morning brief"] or
      (words <= 10 and
         Regex.match?(~r/\b(what'?s|what is|anything)\b.*\b(due|on|up|need(ed)?|going on)\b.*\b(today|this morning|tonight)\b|\b(today'?s|morning) (rundown|brief|list)\b|\bwhat do i (need|have) to do today\b/, t))
  end

  @doc "What's due today, said plainly. `only` limits it to the animals named."
  def brief(today, only \\ []) do
    animals =
      case only do
        [] -> Repo.all(from a in Animal, where: a.owned == true and a.status == "active", order_by: a.name)
        some -> some
      end

    lines =
      Enum.flat_map(animals, fn a ->
        full = Animals.get_animal_with_pedigree!(a.id)
        name = Animal.display_name(a)

        doses =
          full.records
          |> CareSchedule.active_courses(today)
          |> Enum.filter(&(&1.today_i != nil))
          |> Enum.map(fn c ->
            if c.today_given?,
              do: "#{name}'s #{c.record.title}, day #{c.today_i + 1} of #{c.total}, is already given.",
              else: "#{name} is due #{c.record.title} today, day #{c.today_i + 1} of #{c.total}."
          end)

        due =
          full.records
          |> CareSchedule.status(today)
          |> Enum.filter(&(&1.days <= 14))
          |> Enum.sort_by(& &1.days)
          |> Enum.map(fn s ->
            what = s.record.title

            cond do
              s.days < 0 -> "#{name}'s #{what} is #{-s.days} #{plural(-s.days, "day")} overdue."
              s.days == 0 -> "#{name}'s #{what} is due today."
              s.days == 1 -> "#{name}'s #{what} is due tomorrow."
              true -> "#{name}'s #{what} is due in #{s.days} days."
            end
          end)

        doses ++ due ++ training(a, name, today)
      end)

    case lines do
      [] ->
        "Nothing's due today. You're all caught up."

      lines ->
        lines |> Enum.take(8) |> Enum.join(" ")
    end
  end

  defp training(%Animal{id: id}, name, today) do
    with %{} = book <- Training.active_book_for_animal(id),
         %{} = last <- Training.last_session(book.id) do
      case Date.diff(today, last.date) do
        0 -> ["#{name} was already worked today."]
        1 -> ["#{name} was last worked yesterday."]
        n when n > 1 -> ["#{name} was last worked #{n} days ago."]
        _ -> []
      end
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"
end
