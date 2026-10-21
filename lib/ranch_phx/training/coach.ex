defmodule RanchPhx.Training.Coach do
  @moduledoc """
  The Coach: Claude answers training questions about one horse's book.

  Claude starts from a small snapshot (horse, age, stage and its limits, goals,
  open Working on items, the last week) and looks up the rest with tools: sessions
  over a date range, per-activity results by side, one Working on item's history,
  and the program's stages. The server computes every number; Claude explains.

  It suggests, never diagnoses, and points to a vet for anything physical.

  Env vars:
    ANTHROPIC_API_KEY   required to turn the Coach on
    RANCH_AI_MODEL      optional, default "claude-sonnet-5-5"
  """
  import Ecto.Query
  require Logger
  alias RanchPhx.Repo
  alias RanchPhx.Training
  alias RanchPhx.Training.{Book, CoachMessage, Session, SessionActivity, SessionIssue}

  @api "https://api.anthropic.com/v1/messages"
  @questions_per_day 30
  @max_rounds 6
  @max_tokens 16_000
  @max_sessions 60

  @system """
  You are the Coach in a horse training log. You help one trainer think through the
  training of one horse at a time, using what they've logged. You can look things up
  with tools; use them instead of guessing.

  How to work:
  - For anything about how the horse has been, trends, sides, or what to do next, look at
    the logged sessions first. Prefer one or two well-chosen lookups over many small ones.
  - Dates are YYYY-MM-DD. "Lately" means about the last 3 weeks unless they say otherwise.
  - Base what you say on the snapshot and tool results. Never invent sessions, numbers, or
    results. If there isn't enough logged to tell, say so and say what to log next time.
  - Respect the stage's limits on session length and sessions per week, and the horse's age.
    Young horses' growth plates are still open; never suggest more than the stage allows.
  - Suggestions should be concrete and small: what to work on, how long, what to watch for,
    when to quit. Tie them to the goals and the open Working on items when they fit.
  - Never diagnose. If anything sounds physical (sore, lame, off, heat or swelling, not
    eating, a change in how he moves), say plainly that it's worth having the vet look, and
    suggest rest until then.
  - You are not the only voice: the trainer knows the horse. Offer, don't order.

  How to write:
  - Plain, specific, warm. Lead with the answer. Under 200 words unless they ask for detail.
  - Name dates ("Tue Oct 14"), activities, and sides. Short paragraphs; a few short lines
    starting with "- " are fine for a plan. No headings, no tables, no bold.
  """

  def configured?, do: api_key() != nil

  defp api_key do
    case Application.get_env(:ranch_phx, :anthropic_api_key) ||
           System.get_env("ANTHROPIC_API_KEY") do
      nil -> nil
      "" -> nil
      key -> String.trim(key)
    end
  end

  defp model, do: System.get_env("RANCH_AI_MODEL") || "claude-sonnet-5-5"

  # ── Asking ──────────────────────────────────────────────────────────────────

  @doc """
  Ask about a book. Returns `{:ok, %CoachMessage{}}` (the saved question and answer,
  with what was looked up) or `{:error, reason}`; see `error_message/1`.
  """
  def ask(%Book{} = book, question, %Date{} = today) do
    question = String.trim(question || "")

    cond do
      question == "" ->
        {:error, :empty}

      not configured?() ->
        {:error, :no_api_key}

      asked_recently(book.id) >= @questions_per_day ->
        {:error, :limit}

      true ->
        prompt = """
        Today is #{Date.to_iso8601(today)} (#{Calendar.strftime(today, "%A")}).
        Snapshot of #{book.horse.name}'s training book (JSON):
        #{Jason.encode!(snapshot(book, today))}

        The trainer asks: "#{question}"
        """

        with {:ok, text, checked, model} <-
               loop(book, today, base_body(), [%{role: "user", content: prompt}], 0, []) do
          %CoachMessage{
            book_id: book.id,
            question: question,
            answer: text,
            checked: checked |> Enum.reject(&is_nil/1) |> Enum.uniq(),
            model: model
          }
          |> Repo.insert()
        end
    end
  end

  def recent(book_id, limit \\ 5) do
    Repo.all(
      from m in CoachMessage,
        where: m.book_id == ^book_id,
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^limit
    )
  end

  # Questions in the last 24 hours, so the limit doesn't depend on time zones.
  defp asked_recently(book_id) do
    start = NaiveDateTime.utc_now() |> NaiveDateTime.add(-24 * 3600)

    Repo.aggregate(
      from(m in CoachMessage, where: m.book_id == ^book_id and m.inserted_at >= ^start),
      :count
    )
  end

  defp base_body do
    tools = tool_definitions()

    %{
      model: model(),
      max_tokens: @max_tokens,
      output_config: %{effort: "medium"},
      # If a safety classifier declines, the API retries on its recommended model.
      fallbacks: "default",
      # The instructions and tools are the same on every call, so cache them.
      system: [%{type: "text", text: @system, cache_control: %{type: "ephemeral"}}],
      tools: List.update_at(tools, -1, &Map.put(&1, :cache_control, %{type: "ephemeral"}))
    }
  end

  # Ask, run any lookups it calls, and repeat until it answers (at most @max_rounds rounds).
  # The assistant's content goes back exactly as received (thinking and fallback blocks included).
  defp loop(book, today, body, messages, round, checked) do
    body = if round >= @max_rounds, do: Map.put(body, :tool_choice, %{type: "none"}), else: body

    with {:ok, resp} <- request(Map.put(body, :messages, messages)) do
      content = resp["content"] || []
      calls = Enum.filter(content, &(&1["type"] == "tool_use"))

      cond do
        resp["stop_reason"] == "refusal" ->
          {:error, :refusal}

        calls == [] ->
          case text_of(content) do
            "" -> {:error, :empty_answer}
            text -> {:ok, text, checked, resp["model"]}
          end

        true ->
          results = Enum.map(calls, &call_tool(book, today, &1))

          messages =
            messages ++
              [
                %{role: "assistant", content: content},
                %{role: "user", content: Enum.map(results, &elem(&1, 0))}
              ]

          loop(book, today, body, messages, round + 1, checked ++ Enum.map(results, &elem(&1, 1)))
      end
    end
  end

  defp call_tool(book, today, %{"id" => id, "name" => name, "input" => input}) do
    {result, label} =
      try do
        run_tool(book, today, name, input)
      rescue
        e ->
          Logger.warning("Coach tool #{name} failed: #{Exception.message(e)}")
          {%{error: "That lookup failed."}, nil}
      end

    {%{type: "tool_result", tool_use_id: id, content: Jason.encode!(result)}, label}
  end

  # ── Snapshot ────────────────────────────────────────────────────────────────

  @doc "The small starting picture Claude gets; tools fetch the rest."
  def snapshot(%Book{} = book, %Date{} = today) do
    p = Training.progress(book, today)
    horse = book.horse
    week = Training.week_summary(book.id, today)

    %{
      horse:
        %{
          name: horse.name,
          age_months: p.age_months,
          foaled_on: horse.foaled_on && Date.to_iso8601(horse.foaled_on),
          sex: horse.sex,
          breed: horse.breed,
          owner: horse.owner,
          notes: horse.notes
        }
        |> compact(),
      program: book.program.name,
      current_stage: p.stage && stage_info(p.stage),
      stage_set_by_hand: p.overridden?,
      next_stage:
        p.next &&
          %{
            name: p.next.name,
            from_age_months: p.next.from_age_months,
            months_away: p.months_to_next
          },
      goals:
        for g <- book.goals, g.status == "active" do
          compact(%{
            title: g.title,
            target_date: g.target_date && Date.to_iso8601(g.target_date),
            notes: g.notes
          })
        end,
      working_on:
        for i <- Training.list_issues(book.horse_id), i.status != "solved" do
          compact(%{
            id: i.id,
            title: i.title,
            status: i.status,
            activity: i.activity && i.activity.name,
            side: i.side,
            since: Date.to_iso8601(i.opened_on),
            last_marks:
              i.marks
              |> Enum.take(5)
              |> Enum.map(&"#{Date.to_iso8601(&1.session.date)} #{&1.progress}")
          })
        end,
      last_7_days: %{sessions: week.sessions, minutes: week.minutes},
      recent_sessions: book.id |> Training.list_sessions(5) |> Enum.map(&session_info/1)
    }
  end

  defp stage_info(s) do
    compact(%{
      name: s.name,
      summary: s.summary,
      focus: s.focus,
      guardrail: s.guardrail,
      max_minutes_per_session: s.max_session_minutes,
      max_sessions_per_week: s.max_sessions_per_week
    })
  end

  defp session_info(%Session{} = s) do
    compact(%{
      date: Date.to_iso8601(s.date),
      minutes: s.minutes,
      activities:
        Enum.map(s.activities, fn a ->
          compact(%{name: a.activity.name, result: a.result, side: a.side, note: a.note})
        end),
      tags: if(s.tags != [], do: s.tags),
      working_on:
        if s.issue_marks != [] do
          Enum.map(
            s.issue_marks,
            &compact(%{item: &1.issue.title, progress: &1.progress, note: &1.note})
          )
        end,
      note: s.note,
      photos: if(s.photos != [], do: length(s.photos))
    })
  end

  defp compact(map), do: Map.reject(map, fn {_k, v} -> v in [nil, "", []] end)

  # ── Tools ───────────────────────────────────────────────────────────────────

  defp tool_definitions do
    date = %{type: "string", description: "YYYY-MM-DD"}

    [
      %{
        name: "list_sessions",
        description:
          "Logged sessions between two dates (inclusive), newest first, with activities, results, sides, tags, Working on marks and notes. " <>
            "Optionally only sessions that include one activity (by name, e.g. \"Feet\"). At most #{@max_sessions} are returned.",
        strict: true,
        input_schema: %{
          type: "object",
          properties: %{
            from: date,
            to: date,
            activity: %{
              type: ["string", "null"],
              description: "Activity name to filter by, or null for all."
            }
          },
          required: ["from", "to", "activity"],
          additionalProperties: false
        }
      },
      %{
        name: "activity_results",
        description:
          "For each activity between two dates: how many sessions included it, and how many were marked good, mixed or trouble, broken down by side. " <>
            "Use for questions about sides, trends, or what's going well.",
        strict: true,
        input_schema: %{
          type: "object",
          properties: %{from: date, to: date},
          required: ["from", "to"],
          additionalProperties: false
        }
      },
      %{
        name: "working_on_history",
        description:
          "Every session mark (better / same / worse, with notes) for one Working on item, newest first. Use the id from the snapshot.",
        strict: true,
        input_schema: %{
          type: "object",
          properties: %{id: %{type: "integer"}},
          required: ["id"],
          additionalProperties: false
        }
      },
      %{
        name: "program_stages",
        description:
          "All stages of this horse's training program with their ages, focus, and limits.",
        strict: true,
        input_schema: %{
          type: "object",
          properties: %{},
          required: [],
          additionalProperties: false
        }
      }
    ]
  end

  defp run_tool(book, _today, "list_sessions", %{"from" => from, "to" => to} = input) do
    {from, to} = {Date.from_iso8601!(from), Date.from_iso8601!(to)}
    activity = input["activity"]

    query =
      from s in Session,
        where: s.book_id == ^book.id and s.date >= ^from and s.date <= ^to,
        order_by: [desc: s.date, desc: s.inserted_at],
        limit: @max_sessions,
        preload: [:photos, activities: :activity, issue_marks: :issue]

    query =
      if activity in [nil, ""] do
        query
      else
        name = String.downcase(activity)

        from s in query,
          where:
            s.id in subquery(
              from sa in SessionActivity,
                join: a in assoc(sa, :activity),
                where: fragment("lower(?)", a.name) == ^name,
                select: sa.session_id
            )
      end

    sessions = Repo.all(query)
    label = "sessions #{short(from)}–#{short(to)}#{if activity, do: " (#{activity})"}"
    {%{count: length(sessions), sessions: Enum.map(sessions, &session_info/1)}, label}
  end

  defp run_tool(book, _today, "activity_results", %{"from" => from, "to" => to}) do
    {from, to} = {Date.from_iso8601!(from), Date.from_iso8601!(to)}

    rows =
      Repo.all(
        from sa in SessionActivity,
          join: s in assoc(sa, :session),
          join: a in assoc(sa, :activity),
          where: s.book_id == ^book.id and s.date >= ^from and s.date <= ^to,
          group_by: [a.name, sa.result, sa.side],
          select: {a.name, sa.result, sa.side, count(sa.id)}
      )

    activities =
      rows
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.map(fn {name, rs} ->
        %{
          activity: name,
          times: rs |> Enum.map(&elem(&1, 3)) |> Enum.sum(),
          results:
            for {_, result, side, n} <- rs, result || side do
              compact(%{result: result || "not marked", side: side, count: n})
            end
        }
      end)
      |> Enum.sort_by(&(-&1.times))

    {%{from: Date.to_iso8601(from), to: Date.to_iso8601(to), activities: activities},
     "activity results #{short(from)}–#{short(to)}"}
  end

  defp run_tool(book, _today, "working_on_history", %{"id" => id}) do
    case Enum.find(Training.list_issues(book.horse_id), &(&1.id == id)) do
      nil ->
        {%{error: "No Working on item with that id for this horse."}, nil}

      i ->
        marks =
          Enum.map(i.marks, fn %SessionIssue{} = m ->
            compact(%{date: Date.to_iso8601(m.session.date), progress: m.progress, note: m.note})
          end)

        {%{title: i.title, status: i.status, since: Date.to_iso8601(i.opened_on), marks: marks},
         "history of “#{i.title}”"}
    end
  end

  defp run_tool(book, _today, "program_stages", _input) do
    stages =
      for s <- book.program.stages do
        stage_info(s) |> Map.put(:from_age_months, s.from_age_months)
      end

    {%{program: book.program.name, stages: stages}, "program stages"}
  end

  defp run_tool(_book, _today, name, _input), do: {%{error: "Unknown tool #{name}."}, nil}

  defp short(date), do: Calendar.strftime(date, "%b %-d")

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp text_of(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n\n", & &1["text"])
    |> String.trim()
  end

  defp request(body) do
    opts =
      Keyword.merge(
        [
          json: body,
          headers: [
            {"x-api-key", api_key()},
            {"anthropic-version", "2023-06-01"},
            {"anthropic-beta", "server-side-fallback-2026-07-01"}
          ],
          receive_timeout: 120_000,
          retry: :transient
        ],
        Application.get_env(:ranch_phx, :coach_req_options, [])
      )

    case Req.post(@api, opts) do
      {:ok, %{status: 200, body: resp}} ->
        if resp["stop_reason"] == "max_tokens",
          do: Logger.warning("Coach reply hit max_tokens (#{inspect(resp["usage"])})")

        {:ok, resp}

      {:ok, %{status: status, body: resp}} ->
        Logger.warning("Claude API error #{status}: #{inspect(resp) |> String.slice(0, 500)}")
        {:error, {:api, status, resp}}

      {:error, reason} ->
        Logger.warning("Claude API unreachable: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def error_message(:empty), do: "Type a question first."

  def error_message(:no_api_key),
    do: "The Coach isn't set up yet. Add ANTHROPIC_API_KEY on the server and restart."

  def error_message(:limit),
    do:
      "That's the limit of #{@questions_per_day} questions a day for this horse. Try again later."

  def error_message(:refusal), do: "Claude declined that one. Try asking it a different way."

  def error_message(:empty_answer),
    do: "The Coach couldn't put an answer together. Try asking a different way."

  def error_message({:api, 401, _}),
    do: "The API key was rejected. Check the key on the server and restart."

  def error_message({:api, 400, %{"error" => %{"message" => m}}}),
    do: "The request was rejected: #{String.slice(m, 0, 200)}"

  def error_message({:api, 429, _}), do: "Too many requests right now. Try again in a minute."

  def error_message({:api, s, _}) when s in [500, 529],
    do: "Claude is busy right now. Try again in a minute."

  def error_message(_), do: "Couldn't reach Claude. Try again."
end
