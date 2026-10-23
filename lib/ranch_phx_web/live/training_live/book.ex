defmodule RanchPhxWeb.TrainingLive.Book do
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents
  alias RanchPhx.Training
  alias RanchPhx.Training.Coach
  alias RanchPhx.Training.{Goal, Issue, SessionActivity, SessionIssue}
  alias RanchPhx.Accounts.Scope
  alias RanchPhxWeb.Uploads

  @minute_chips [10, 15, 20, 30, 45]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = Training.get_book!(id)
    offset = if connected?(socket), do: get_connect_params(socket)["tz_offset"], else: nil
    today = Training.today(offset)

    {:ok,
     socket
     |> assign(:page_title, "#{book.horse.name} · Training")
     |> assign(:book, book)
     |> assign(:today, today)
     |> assign(:minute_chips, @minute_chips)
     |> assign(:is_superuser, Scope.superuser?(socket.assigns[:current_scope]))
     |> assign(:gated, Training.gated_activities(book.program))
     |> assign(:tags, Training.list_tags(archived: true))
     |> assign(:profile_form, nil)
     |> assign(:goal_form, nil)
     |> assign(:editing_goal, nil)
     |> assign(:show_done_goals, false)
     |> assign(:issue_form, nil)
     |> assign(:editing_issue, nil)
     |> assign(:issue_history, nil)
     |> assign(:show_solved, false)
     |> assign(:naming_routine, false)
     |> assign(:managing_routines, false)
     |> assign(:routine_error, nil)
     |> assign(:lightbox, nil)
     |> assign(:coach_on, Coach.configured?())
     |> assign_coach_threads()
     |> assign(:coach_question, "")
     |> assign(:coach_loading, nil)
     |> assign(:coach_error, nil)
     |> allow_upload(:photo,
       accept: Uploads.image_types(),
       max_entries: 1,
       max_file_size: 20_000_000
     )
     # Uploads start as soon as photos are picked, so they're done by the time
     # the rest of the form is filled in.
     |> allow_upload(:session_photos,
       accept: Uploads.image_types(),
       max_entries: 8,
       max_file_size: 25_000_000,
       auto_upload: true
     )
     |> reset_form()
     |> load()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # ── Log form ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("change", %{"session" => params} = payload, socket) do
    {:noreply,
     socket
     |> assign(:params, normalize(params, payload["_target"], socket.assigns.params))
     |> put_warnings()}
  end

  def handle_event("save", %{"session" => params}, socket) do
    params = normalize(params, nil, socket.assigns.params)

    with true <- socket.assigns.is_superuser,
         :ok <- photos_ready(socket),
         {:ok, session} <-
           Training.save_session(to_attrs(params, socket.assigns.book.id, socket.assigns.issues)) do
      save_session_photos(socket, session)

      {:noreply,
       socket
       |> put_flash(
         :info,
         if(socket.assigns.editing, do: "Session updated", else: "Session saved")
       )
       |> reset_form(params["date"])
       |> load()}
    else
      false ->
        {:noreply, socket}

      {:uploading, msg} ->
        {:noreply, socket |> assign(:params, params) |> assign(:errors, [msg])}

      {:error, changeset} ->
        errors =
          Enum.map(changeset.errors, fn {field, {msg, _}} ->
            "#{Phoenix.Naming.humanize(field)} #{msg}"
          end)

        {:noreply, socket |> assign(:params, params) |> assign(:errors, errors)}
    end
  end

  def handle_event("repeat_last", _params, socket) do
    case Training.last_session(socket.assigns.book.id) do
      nil ->
        {:noreply, socket}

      last ->
        ids = Enum.map(last.activities, & &1.activity_id)
        {:noreply, socket |> fill_from(ids, last.minutes, last.tags) |> put_warnings()}
    end
  end

  def handle_event("apply_routine", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.routines, &("#{&1.id}" == id)) do
      nil -> {:noreply, socket}
      r -> {:noreply, socket |> fill_from(r.activity_ids, r.minutes, r.tags) |> put_warnings()}
    end
  end

  def handle_event("edit_session", %{"id" => id}, socket) do
    s = Training.get_session!(socket.assigns.book.id, id)

    details =
      Map.new(s.activities, fn a ->
        {"#{a.activity_id}", %{"result" => a.result, "side" => a.side, "note" => a.note || ""}}
      end)

    params =
      socket.assigns.today
      |> blank_params(Date.to_iso8601(s.date))
      |> Map.merge(%{
        "client_id" => s.client_id,
        "activity_ids" => Enum.map(s.activities, &"#{&1.activity_id}"),
        "details" => details,
        "tags" => s.tags,
        "note" => s.note || "",
        "issues" =>
          Map.new(s.issue_marks, fn m ->
            {"#{m.issue_id}", %{"progress" => m.progress, "note" => m.note || ""}}
          end)
      })
      |> put_minutes(s.minutes)

    {:noreply,
     socket
     |> assign(:editing_photos, s.photos)
     |> assign(:editing, s.id)
     |> assign(:params, params)
     |> assign(:errors, [])
     |> put_activity_options()
     |> put_warnings()}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> reset_form() |> put_activity_options() |> put_warnings()}
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    if socket.assigns.is_superuser do
      socket.assigns.book.id |> Training.delete_session(id) |> Enum.each(&Uploads.delete_file/1)
    end

    {:noreply, load(socket)}
  end

  # ── Session photos ──────────────────────────────────────────────────────────

  def handle_event("cancel_session_photo", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :session_photos, ref)}
  end

  def handle_event("remove_photo", %{"id" => id}, socket) do
    with true <- socket.assigns.is_superuser,
         {:ok, url} <- Training.delete_session_photo(socket.assigns.book.id, id) do
      Uploads.delete_file(url)
    end

    {:noreply, load(socket)}
  end

  def handle_event("open_photo", %{"url" => url}, socket),
    do: {:noreply, assign(socket, :lightbox, url)}

  def handle_event("close_photo", _params, socket), do: {:noreply, assign(socket, :lightbox, nil)}

  # ── Routines ────────────────────────────────────────────────────────────────

  def handle_event("name_routine", _params, socket) do
    {:noreply, socket |> assign(:naming_routine, true) |> assign(:routine_error, nil)}
  end

  def handle_event("cancel_routine", _params, socket) do
    {:noreply, assign(socket, :naming_routine, false)}
  end

  def handle_event("create_routine", %{"name" => name}, socket) do
    %{params: p, book: book} = socket.assigns

    attrs = %{
      "horse_id" => book.horse_id,
      "name" => name,
      "activity_ids" => p["activity_ids"],
      "minutes" => p["minutes"],
      "tags" => p["tags"]
    }

    with true <- socket.assigns.is_superuser,
         {:ok, _} <- Training.create_routine(attrs) do
      {:noreply, socket |> assign(:naming_routine, false) |> load()}
    else
      false ->
        {:noreply, socket}

      {:error, cs} ->
        msg =
          Enum.map_join(cs.errors, ", ", fn
            {:activity_ids, {m, _}} -> m
            {f, {m, _}} -> "#{Phoenix.Naming.humanize(f)} #{m}"
          end)

        {:noreply, assign(socket, :routine_error, msg)}
    end
  end

  def handle_event("toggle_manage_routines", _params, socket) do
    {:noreply, update(socket, :managing_routines, &(!&1))}
  end

  def handle_event("delete_routine", %{"id" => id}, socket) do
    if socket.assigns.is_superuser, do: Training.delete_routine(socket.assigns.book.horse_id, id)
    {:noreply, load(socket)}
  end

  # ── Coach ───────────────────────────────────────────────────────────────────

  def handle_event("coach_ask", %{"question" => q}, socket), do: {:noreply, ask_coach(socket, q)}
  def handle_event("coach_suggest", %{"q" => q}, socket), do: {:noreply, ask_coach(socket, q)}

  def handle_event("coach_typing", %{"question" => q}, socket),
    do: {:noreply, assign(socket, :coach_question, q)}

  def handle_event("coach_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:coach_thread, [])
     |> assign(:coach_question, "")
     |> assign(:coach_error, nil)}
  end

  def handle_event("coach_open", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(
       :coach_thread,
       Coach.thread_messages(socket.assigns.book.id, String.to_integer(id))
     )
     |> assign(:coach_error, nil)}
  end

  # ── Working on ──────────────────────────────────────────────────────────────

  def handle_event("new_issue", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_issue, :new)
     |> assign(:issue_form, to_form(Training.change_issue(%Issue{})))}
  end

  def handle_event("edit_issue", %{"id" => id}, socket) do
    issue = Training.get_issue!(socket.assigns.book.horse_id, id)

    {:noreply,
     socket
     |> assign(:editing_issue, issue.id)
     |> assign(:issue_form, to_form(Training.change_issue(issue)))}
  end

  def handle_event("cancel_issue", _params, socket) do
    {:noreply, socket |> assign(:editing_issue, nil) |> assign(:issue_form, nil)}
  end

  def handle_event("save_issue", %{"issue" => params}, socket) do
    %{book: book, editing_issue: editing, today: today} = socket.assigns

    params =
      params
      |> Map.take(["title", "activity_id", "side", "notes"])
      |> Map.new(fn {k, v} -> {k, blank_to_nil(v)} end)

    result =
      cond do
        not socket.assigns.is_superuser -> :skip
        editing == :new -> Training.create_issue(book.horse_id, params, today)
        true -> book.horse_id |> Training.get_issue!(editing) |> Training.update_issue(params)
      end

    case result do
      {:error, cs} ->
        {:noreply, assign(socket, :issue_form, to_form(cs))}

      _ ->
        {:noreply, socket |> assign(:editing_issue, nil) |> assign(:issue_form, nil) |> load()}
    end
  end

  def handle_event("issue_status", %{"id" => id, "status" => status}, socket) do
    if socket.assigns.is_superuser do
      socket.assigns.book.horse_id
      |> Training.get_issue!(id)
      |> Training.set_issue_status(status, socket.assigns.today)
    end

    {:noreply, load(socket)}
  end

  def handle_event("delete_issue", %{"id" => id}, socket) do
    if socket.assigns.is_superuser do
      socket.assigns.book.horse_id |> Training.get_issue!(id) |> Training.delete_issue()
    end

    {:noreply, socket |> assign(:editing_issue, nil) |> assign(:issue_form, nil) |> load()}
  end

  def handle_event("toggle_issue_history", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, update(socket, :issue_history, &if(&1 == id, do: nil, else: id))}
  end

  def handle_event("toggle_solved", _params, socket) do
    {:noreply, update(socket, :show_solved, &(!&1))}
  end

  # ── Goals ───────────────────────────────────────────────────────────────────

  def handle_event("new_goal", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_goal, :new)
     |> assign(:goal_form, to_form(Training.change_goal(%Goal{})))}
  end

  def handle_event("edit_goal", %{"id" => id}, socket) do
    goal = Training.get_goal!(socket.assigns.book.id, id)

    {:noreply,
     socket
     |> assign(:editing_goal, goal.id)
     |> assign(:goal_form, to_form(Training.change_goal(goal)))}
  end

  def handle_event("cancel_goal", _params, socket) do
    {:noreply, socket |> assign(:editing_goal, nil) |> assign(:goal_form, nil)}
  end

  def handle_event("save_goal", %{"goal" => params}, socket) do
    %{book: book, editing_goal: editing} = socket.assigns
    params = Map.take(params, ["title", "target_date", "notes"])

    result =
      cond do
        not socket.assigns.is_superuser -> :skip
        editing == :new -> Training.create_goal(book, params)
        true -> book.id |> Training.get_goal!(editing) |> Training.update_goal(params)
      end

    case result do
      {:error, cs} ->
        {:noreply, assign(socket, :goal_form, to_form(cs))}

      _ ->
        {:noreply,
         socket |> assign(:editing_goal, nil) |> assign(:goal_form, nil) |> reload_book()}
    end
  end

  def handle_event("goal_status", %{"id" => id, "status" => status}, socket) do
    if socket.assigns.is_superuser and status in Goal.statuses() do
      socket.assigns.book.id
      |> Training.get_goal!(id)
      |> Training.set_goal_status(status, socket.assigns.today)
    end

    {:noreply, reload_book(socket)}
  end

  def handle_event("delete_goal", %{"id" => id}, socket) do
    if socket.assigns.is_superuser do
      socket.assigns.book.id |> Training.get_goal!(id) |> Training.delete_goal()
    end

    {:noreply, socket |> assign(:editing_goal, nil) |> assign(:goal_form, nil) |> reload_book()}
  end

  def handle_event("toggle_done_goals", _params, socket) do
    {:noreply, update(socket, :show_done_goals, &(!&1))}
  end

  # ── Profile ─────────────────────────────────────────────────────────────────

  def handle_event("edit_profile", _params, socket) do
    {:noreply,
     assign(socket, :profile_form, to_form(Training.change_horse(socket.assigns.book.horse)))}
  end

  def handle_event("cancel_profile", _params, socket) do
    {:noreply, assign(socket, :profile_form, nil)}
  end

  def handle_event("validate_profile", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_photo", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("save_profile", %{"horse" => params}, socket) do
    horse = socket.assigns.book.horse

    with true <- socket.assigns.is_superuser,
         {:ok, horse} <- Training.update_horse(horse, Map.delete(params, "animal_id")) do
      had_photo? = socket.assigns.uploads.photo.entries != []

      [url | _] =
        consume_uploaded_entries(socket, :photo, fn %{path: tmp}, entry ->
          {:ok, Uploads.save_image(tmp, entry.client_name, "training/horses/#{horse.id}")}
        end) ++ [nil]

      if url, do: Training.set_horse_photo(horse, url)

      {:noreply,
       socket
       |> assign(:profile_form, nil)
       |> put_flash(
         :info,
         if(had_photo? and is_nil(url),
           do: "Saved, but the photo didn't upload. Try again.",
           else: "Profile saved"
         )
       )
       |> reload_book()}
    else
      false -> {:noreply, socket}
      {:error, changeset} -> {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  def handle_event("set_stage", params, socket) do
    if socket.assigns.is_superuser do
      stage_id =
        with %{"id" => id} <- params, {int, ""} <- Integer.parse(id), do: int, else: (_ -> nil)

      {:ok, _} = Training.set_stage_override(socket.assigns.book, stage_id)
      {:noreply, reload_book(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  # The Coach may have added a Working on item, so the page reloads too.
  def handle_async(:coach, {:ok, {:ok, message}}, socket) do
    {:noreply,
     socket
     |> assign(:coach_loading, nil)
     |> assign(:coach_question, "")
     |> assign_coach_threads(message.id)
     |> load()}
  end

  def handle_async(:coach, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket |> assign(:coach_loading, nil) |> assign(:coach_error, Coach.error_message(reason))}
  end

  def handle_async(:coach, {:exit, reason}, socket) do
    require Logger
    Logger.error("Coach crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:coach_loading, nil)
     |> assign(:coach_error, "Something went wrong asking the TrAIner. Try again.")}
  end

  # Runs in the background: the lookups can take several seconds.
  defp ask_coach(socket, question) do
    %{book: book, today: today, is_superuser: superuser?, coach_loading: loading} = socket.assigns
    thread_id = socket.assigns.coach_thread |> List.first() |> then(&(&1 && &1.id))
    question = String.trim(question || "")

    cond do
      not superuser? or loading != nil or question == "" ->
        socket

      true ->
        socket
        |> assign(:coach_loading, question)
        |> assign(:coach_error, nil)
        |> start_async(:coach, fn -> Coach.ask(book, question, today, thread_id) end)
    end
  end

  # Opens the conversation `message_id` belongs to, or the most recent one.
  defp assign_coach_threads(socket, message_id \\ nil) do
    book_id = socket.assigns.book.id
    threads = Coach.recent_threads(book_id)
    open_id = message_id || threads |> List.first() |> then(&(&1 && &1.id))

    socket
    |> assign(:coach_threads, threads)
    |> assign(:coach_thread, if(open_id, do: Coach.thread_messages(book_id, open_id), else: []))
  end

  # ── Form state ──────────────────────────────────────────────────────────────

  defp photos_ready(socket) do
    if Enum.all?(socket.assigns.uploads.session_photos.entries, & &1.done?),
      do: :ok,
      else: {:uploading, "Photos are still uploading. Give it a moment, then save again."}
  end

  defp save_session_photos(socket, session) do
    urls =
      consume_uploaded_entries(socket, :session_photos, fn %{path: tmp}, entry ->
        {:ok, Uploads.save_image(tmp, entry.client_name, "training/sessions/#{session.id}")}
      end)
      |> Enum.reject(&is_nil/1)

    Training.add_session_photos(session, urls)
  end

  # The form sends everything each time; hidden "" placeholders mean "none picked".
  # Minutes and the date come from a quick-pick button or the typed box, whichever
  # was touched last. The client_id stays the one generated (or edited) server-side.
  defp normalize(params, target, previous) do
    params =
      params
      |> Map.put("client_id", previous["client_id"])
      |> Map.update("tags", [], &clean_list/1)
      |> Map.update("activity_ids", [], &clean_list/1)
      |> Map.put_new("details", %{})
      |> Map.put_new("issues", %{})

    params =
      case target do
        ["session", "minute_chip"] -> Map.put(params, "minutes_typed", "")
        ["session", "minutes_typed"] -> Map.delete(params, "minute_chip")
        ["session", "date_chip"] -> Map.put(params, "date_typed", "")
        ["session", "date_typed"] -> Map.delete(params, "date_chip")
        _ -> params
      end

    params
    |> Map.put("minutes", pick(params["minutes_typed"], params["minute_chip"]))
    |> Map.put("date", pick(params["date_typed"], params["date_chip"]))
  end

  defp clean_list(list), do: list |> List.wrap() |> Enum.reject(&(&1 == "")) |> Enum.uniq()

  defp pick(typed, chip) when typed in [nil, ""], do: chip
  defp pick(typed, _chip), do: typed

  defp to_attrs(params, book_id, issues) do
    known = MapSet.new(issues, &"#{&1.id}")

    marks =
      for {id, m} <- params["issues"],
          MapSet.member?(known, id),
          m["progress"] in ~w(better same worse),
          do: %{"issue_id" => id, "progress" => m["progress"], "note" => blank_to_nil(m["note"])}

    activities =
      for id <- params["activity_ids"] do
        d = Map.get(params["details"], id, %{})

        %{
          "activity_id" => id,
          "result" => blank_to_nil(d["result"]),
          "side" => blank_to_nil(d["side"]),
          "note" => blank_to_nil(d["note"])
        }
      end

    params
    |> Map.take(["client_id", "date", "minutes", "tags", "note"])
    |> Map.put("book_id", book_id)
    |> Map.put("activities", activities)
    |> Map.put("issues", marks)
  end

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: v

  defp blank_params(today, date) do
    chip? = date in Enum.map(date_chips(today), &elem(&1, 0))

    %{
      "client_id" => Ecto.UUID.generate(),
      "date" => date,
      "date_chip" => if(chip?, do: date),
      "date_typed" => if(chip?, do: "", else: date),
      "activity_ids" => [],
      "details" => %{},
      "minute_chip" => nil,
      "minutes_typed" => "",
      "minutes" => nil,
      "tags" => [],
      "note" => "",
      "issues" => %{}
    }
  end

  defp put_minutes(params, nil), do: params

  defp put_minutes(params, minutes) do
    if minutes in @minute_chips,
      do:
        Map.merge(params, %{
          "minute_chip" => "#{minutes}",
          "minutes_typed" => "",
          "minutes" => "#{minutes}"
        }),
      else:
        Map.merge(params, %{
          "minute_chip" => nil,
          "minutes_typed" => "#{minutes}",
          "minutes" => "#{minutes}"
        })
  end

  # Repeat last / routine: fill activities, minutes and tags; keep the day and the note.
  defp fill_from(socket, activity_ids, minutes, tags) do
    params =
      socket.assigns.params
      |> Map.merge(%{
        "activity_ids" => Enum.map(activity_ids, &"#{&1}"),
        "details" => %{},
        "tags" => tags,
        "minute_chip" => nil,
        "minutes_typed" => "",
        "minutes" => nil
      })
      |> put_minutes(minutes)

    socket |> assign(:params, params) |> put_activity_options()
  end

  # Keeps the last date used, so several past days can be logged in a row.
  defp reset_form(socket, date \\ nil) do
    date = date || Date.to_iso8601(socket.assigns.today)

    socket
    |> assign(:params, blank_params(socket.assigns.today, date))
    |> assign(:editing, nil)
    |> assign(:editing_photos, [])
    |> assign(:errors, [])
    |> assign(:warnings, [])
  end

  defp reload_book(socket) do
    socket |> assign(:book, Training.get_book!(socket.assigns.book.id)) |> load()
  end

  defp load(socket) do
    %{book: book, today: today} = socket.assigns
    sessions = Training.list_sessions(book.id)

    editing_photos =
      case Enum.find(sessions, &(&1.id == socket.assigns[:editing])) do
        nil -> []
        s -> s.photos
      end

    socket
    |> assign(:editing_photos, editing_photos)
    |> assign(:progress, Training.progress(book, today))
    |> assign(:week, Training.week_summary(book.id, today))
    |> assign(:sessions, sessions)
    |> assign(:routines, Training.list_routines(book.horse_id))
    |> assign(:issues, Training.list_issues(book.horse_id))
    |> put_activity_options()
    |> put_warnings()
  end

  # Most-used activities for this horse first; hidden ones only when this session uses them.
  defp put_activity_options(socket) do
    usage = Training.activity_usage(socket.assigns.book.id, socket.assigns.today)
    selected = socket.assigns.params["activity_ids"]

    options =
      Training.list_activities(archived: true)
      |> Enum.filter(&(not &1.archived or "#{&1.id}" in selected))
      |> Enum.sort_by(&{-Map.get(usage, &1.id, 0), &1.position})

    assign(socket, :activities, options)
  end

  defp put_warnings(socket) do
    %{params: params, progress: progress, week: week, activities: activities, gated: gated} =
      socket.assigns

    minutes =
      case Integer.parse("#{params["minutes"]}") do
        {m, _} -> m
        :error -> nil
      end

    picked = Enum.filter(activities, &("#{&1.id}" in params["activity_ids"]))
    # An edit shouldn't count its own session twice against the week.
    week =
      if socket.assigns.editing,
        do: %{week | sessions: max(week.sessions - 1, 0)},
        else: week

    assign(
      socket,
      :warnings,
      Training.guardrail_warnings(
        progress.stage,
        %{minutes: minutes, activities: picked},
        week,
        gated
      )
    )
  end

  # ── Template helpers ────────────────────────────────────────────────────────

  def sex_label("stallion"), do: "Stud"
  def sex_label("gelding"), do: "Gelding"
  def sex_label("mare"), do: "Mare"
  def sex_label(other), do: other

  def date_chips(today) do
    [{Date.to_iso8601(today), "Today"}, {Date.to_iso8601(Date.add(today, -1)), "Yesterday"}]
  end

  def coach_suggestions(book) do
    [
      "What should I work on this week?",
      "How's he been on his left side lately?",
      "Is he ready for the next stage?",
      "Something's giving us trouble. Help me work through it.",
      if(book.horse.foaled_on, do: "Anything I'm overdoing for his age?")
    ]
    |> Enum.reject(&is_nil/1)
  end

  def results, do: SessionActivity.results()
  def progress_options, do: SessionIssue.progress_options()
  def issue_statuses, do: Issue.statuses()

  def mark(params, id, key), do: get_in(params, ["issues", "#{id}", key])

  @doc "Issues shown on the log form: open ones, plus any this session already marks."
  def loggable_issues(issues, params) do
    Enum.filter(issues, &(&1.status != "solved" or Map.has_key?(params["issues"], "#{&1.id}")))
  end

  def progress_icon("better"), do: "↑"
  def progress_icon("same"), do: "="
  def progress_icon("worse"), do: "↓"

  def issue_meta(issue) do
    [issue.activity && issue.activity.name, issue.side && side_label(issue.side)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  def sides, do: SessionActivity.sides()

  def detail(params, id, key), do: get_in(params, ["details", "#{id}", key])

  def tag_name(tags, slug) do
    case Enum.find(tags, &(&1.slug == slug)) do
      nil -> slug
      t -> t.name
    end
  end

  def health_tag?(tags, slug), do: Enum.any?(tags, &(&1.slug == slug and &1.kind == "health"))

  def activity_summary(routine, activities) do
    routine.activity_ids
    |> Enum.map(fn id -> Enum.find_value(activities, &(&1.id == id && &1.name)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" + ")
  end

  def goal_when(%Goal{target_date: nil}, _today), do: nil

  def goal_when(%Goal{target_date: d}, today) do
    days = Date.diff(d, today)

    cond do
      days > 1 -> "#{Calendar.strftime(d, "%b %-d, %Y")} · #{days} days"
      days == 1 -> "Tomorrow"
      days == 0 -> "Today"
      true -> "#{Calendar.strftime(d, "%b %-d, %Y")} · #{-days} days ago"
    end
  end

  @doc "Short countdown for a goal's badge: \"in 16 months\", \"in 12 days\", \"Today\"."
  def goal_countdown(%Goal{target_date: nil}, _today), do: nil

  def goal_countdown(%Goal{target_date: d}, today) do
    days = Date.diff(d, today)

    cond do
      days > 90 -> "in #{div(days, 30)} months"
      days > 1 -> "in #{days} days"
      days == 1 -> "Tomorrow"
      days == 0 -> "Today"
      days == -1 -> "1 day past"
      true -> "#{-days} days past"
    end
  end

  def side_label("both"), do: "Both sides"
  def side_label(side), do: "#{String.capitalize(side)} side"

  def fmt_date(iso, today) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> fmt_date(date, today)
      _ -> "–"
    end
  end

  def fmt_date(nil, _today), do: "–"

  def fmt_date(date, today) do
    case Date.diff(today, date) do
      0 -> "Today"
      1 -> "Yesterday"
      _ -> Calendar.strftime(date, "%a %b %-d")
    end
  end
end
