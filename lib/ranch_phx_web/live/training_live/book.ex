defmodule RanchPhxWeb.TrainingLive.Book do
  use RanchPhxWeb, :live_view
  import RanchPhxWeb.TrainingComponents
  import RanchPhxWeb.TrainingTimeline
  alias RanchPhx.Training
  alias RanchPhx.Training.Coach
  alias RanchPhx.Training.Timeline
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
     |> assign(:siri_note, nil)
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
     |> assign(:show_weeks, false)
     |> assign(:tl_stage_id, nil)
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
     |> assign(:voice_text, "")
     |> assign(:voice_loading, false)
     |> assign(:voice_note, nil)
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
  # From the Siri voice log: fill the log form from what was said, to check and save.
  def handle_params(%{"voice" => id}, _uri, socket) do
    note = connected?(socket) && socket.assigns.is_superuser && RanchPhx.VoiceNotes.get(id)
    current = socket.assigns.siri_note

    case note do
      %{status: "pending", animal_id: animal_id} = note when animal_id == socket.assigns.book.horse.animal_id ->
        if current && current.id == note.id do
          {:noreply, socket}
        else
          {:noreply, socket} = handle_event("voice_fill", %{"spoken" => note.text}, assign(socket, :siri_note, note))
          {:noreply, push_event(socket, "ranch:scroll-to", %{id: "log"})}
        end

      _ ->
        {:noreply, socket}
    end
  end

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
      save_spoken_extras(socket, params)
      siri = socket.assigns.siri_note
      if siri, do: RanchPhx.VoiceNotes.mark(siri, "done")

      {:noreply,
       socket
       |> assign(:siri_note, nil)
       |> put_flash(
         :info,
         cond do
           socket.assigns.editing -> "Session updated"
           siri -> "Session saved from your Siri note"
           true -> "Session saved"
         end
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
          Enum.map(changeset.errors, fn
            {:activities, {"pick at least one", _}} -> "Pick at least one activity."
            {field, {msg, _}} -> "#{Phoenix.Naming.humanize(field)} #{msg}"
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

  # "Log this" on the Today card: fill in the suggested activities and length.
  def handle_event("plan_fill", _params, socket) do
    plan = socket.assigns.plan

    {:noreply,
     socket |> fill_from(Enum.map(plan.activities, & &1.id), plan.minutes, []) |> put_warnings()}
  end

  # Talk-to-log: the TrAIner reads what was said and fills in the form to check over.
  def handle_event("voice_typing", %{"spoken" => text}, socket),
    do: {:noreply, assign(socket, :voice_text, text)}

  def handle_event("voice_fill", %{"spoken" => text}, socket) do
    %{book: book, today: today, activities: activities, tags: tags, issues: issues} =
      socket.assigns

    open = loggable_issues(issues, socket.assigns.params)
    live_tags = Enum.reject(tags, & &1.archived)

    cond do
      not socket.assigns.is_superuser or socket.assigns.voice_loading or String.trim(text) == "" ->
        {:noreply, assign(socket, :voice_text, text)}

      true ->
        {:noreply,
         socket
         |> assign(voice_text: text, voice_loading: true, voice_note: nil)
         |> start_async(:voice, fn ->
           Coach.read_session(book, text, today, activities, live_tags, open)
         end)}
    end
  end

  def handle_event("drop_new_issue", %{"i" => i}, socket) do
    params = socket.assigns.params
    list = List.delete_at(params["new_issues"] || [], String.to_integer(i))
    {:noreply, assign(socket, :params, Map.put(params, "new_issues", list))}
  end

  def handle_event("drop_milestone", _params, socket),
    do: {:noreply, assign(socket, :params, Map.put(socket.assigns.params, "milestone", ""))}

  def handle_event("voice_clear", _params, socket),
    do: {:noreply, assign(socket, voice_text: "", voice_note: nil)}

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

  def handle_event("toggle_weeks", _params, socket) do
    {:noreply, update(socket, :show_weeks, &(!&1))}
  end

  # Tapping a stage on the timeline opens it; tapping the open one again closes it.
  def handle_event("tl_stage", %{"id" => id}, socket) do
    id =
      case Integer.parse(to_string(id)) do
        {n, ""} -> n
        _ -> nil
      end

    {:noreply, update(socket, :tl_stage_id, fn open -> if(open == id, do: nil, else: id) end)}
  end

  def handle_event("tl_stage", _params, socket), do: {:noreply, socket}

  def handle_event("tl_close", _params, socket), do: {:noreply, assign(socket, :tl_stage_id, nil)}

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

  def handle_async(:voice, {:ok, {:ok, filled}}, socket) do
    # Anything he did that isn't on the list yet becomes a new activity.
    socket =
      case new_activity_names(filled, socket.assigns.activities) do
        [] ->
          socket

        names ->
          Enum.each(names, &Training.create_activity/1)
          assign(socket, :activities, Training.list_activities())
      end

    {params, summary} = merge_spoken(socket.assigns.params, filled, socket.assigns)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:voice_loading, false)
     |> assign(:voice_note, {:ok, summary})
     |> put_activity_options()
     |> put_warnings()}
  end

  def handle_async(:voice, {:ok, {:error, reason}}, socket) do
    {:noreply,
     assign(socket, voice_loading: false, voice_note: {:error, Coach.error_message(reason)})}
  end

  def handle_async(:voice, {:exit, _reason}, socket) do
    {:noreply,
     assign(socket,
       voice_loading: false,
       voice_note: {:error, "Something went wrong reading that. Try again."}
     )}
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
      # From the TrAIner only (not form fields): kept until saved or removed.
      |> Map.put("new_issues", previous["new_issues"] || [])
      |> Map.put_new("milestone", previous["milestone"] || "")

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

    note =
      case String.trim(params["milestone"] || "") do
        "" -> params["note"]
        m -> String.trim("★ #{m}\n#{params["note"]}")
      end

    params
    |> Map.take(["client_id", "date", "minutes", "tags"])
    |> Map.put("note", note)
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
      "issues" => %{},
      "new_issues" => [],
      "milestone" => ""
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

  # Adds what the TrAIner read from the spoken notes to the form, keeping what's already
  # picked. Returns the new params and a short list of what was filled in.
  @doc false
  def merge_spoken(params, filled, %{activities: activities, today: today} = assigns) do
    by_name = Map.new(activities, &{String.downcase(&1.name), &1})
    known_issues = MapSet.new(assigns.issues, & &1.id)
    known_tags = MapSet.new(assigns.tags, & &1.slug)

    picked =
      for a <- filled["activities"] || [],
          act = by_name[String.downcase(a["activity"] || "")],
          do: {act, a}

    details =
      Enum.reduce(picked, params["details"], fn {act, a}, acc ->
        prev = Map.get(acc, "#{act.id}", %{})

        Map.put(
          acc,
          "#{act.id}",
          prev
          |> put_if("result", a["result"])
          |> put_if("side", a["side"])
          |> put_if("note", a["note"])
        )
      end)

    marks =
      for m <- filled["working_on"] || [],
          MapSet.member?(known_issues, m["id"]),
          m["progress"] in ~w(better same worse),
          into: params["issues"],
          do: {"#{m["id"]}", %{"progress" => m["progress"], "note" => m["note"] || ""}}

    tags = Enum.filter(filled["tags"] || [], &MapSet.member?(known_tags, &1))

    extra =
      [
        filled["behavior"] not in [nil, ""] && "How he was: #{filled["behavior"]}",
        (filled["gear"] || []) != [] && "Gear: #{Enum.join(filled["gear"], ", ")}",
        filled["health"] not in [nil, ""] && "Health: #{filled["health"]}",
        filled["note"] not in [nil, ""] && filled["note"]
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.join("\n")

    note =
      case {String.trim(params["note"] || ""), extra} do
        {_, ""} -> params["note"]
        {"", n} -> n
        {old, n} -> old <> "\n" <> n
      end

    open_titles = MapSet.new(assigns.issues, &String.downcase(&1.title))

    new_issues =
      (params["new_issues"] || []) ++
        for(
          i <- filled["new_working_on"] || [],
          t = String.trim(i["title"] || ""),
          t != "",
          not MapSet.member?(open_titles, String.downcase(t)),
          do: %{"title" => t, "side" => i["side"], "note" => i["note"]}
        )

    new_issues = Enum.uniq_by(new_issues, &String.downcase(&1["title"]))

    milestone =
      case filled["milestone"] do
        m when m in [nil, ""] -> params["milestone"] || ""
        m -> m
      end

    params =
      params
      |> Map.put(
        "activity_ids",
        Enum.uniq(params["activity_ids"] ++ Enum.map(picked, fn {act, _} -> "#{act.id}" end))
      )
      |> Map.put("details", details)
      |> Map.put("issues", marks)
      |> Map.put("tags", Enum.uniq(params["tags"] ++ tags))
      |> Map.put("note", note)
      |> Map.put("new_issues", new_issues)
      |> Map.put("milestone", milestone)
      |> put_minutes(filled["minutes"])
      |> put_spoken_date(filled["date"], today)

    summary =
      [
        picked != [] &&
          "#{length(picked)} #{if length(picked) == 1, do: "activity", else: "activities"}",
        filled["minutes"] && "#{filled["minutes"]} min",
        (filled["working_on"] || []) != [] && "Working on",
        tags != [] && "how he was",
        (filled["new_working_on"] || []) != [] && "new things to work on",
        filled["milestone"] not in [nil, ""] && "a milestone",
        extra != "" && "notes"
      ]
      |> Enum.filter(&is_binary/1)

    {params, summary}
  end

  # What only the TrAIner fills in: new Working on items, and a milestone on the
  # horse's ranch timeline.
  defp save_spoken_extras(socket, params) do
    %{book: book, today: today} = socket.assigns

    for i <- params["new_issues"] || [], String.trim(i["title"] || "") != "" do
      Training.create_issue(
        book.horse_id,
        %{
          "title" => i["title"],
          "side" => blank_to_nil(i["side"]),
          "notes" => blank_to_nil(i["note"])
        },
        today
      )
    end

    with m when m not in [nil, ""] <- String.trim(params["milestone"] || ""),
         animal_id when not is_nil(animal_id) <- book.horse.animal_id,
         {:ok, date} <- Date.from_iso8601(params["date"] || "") do
      RanchPhx.Animals.create_event(%{
        "animal_id" => animal_id,
        "event_type" => "training",
        "title" => m,
        "event_date" => date
      })
    end

    :ok
  end

  @doc """
  New activity names the TrAIner came up with (not in the list yet), so they can be
  added before the rest is filled in.
  """
  def new_activity_names(filled, activities) do
    known = MapSet.new(activities, &String.downcase(&1.name))

    (filled["activities"] || [])
    |> Enum.map(&String.trim(&1["activity"] || ""))
    |> Enum.reject(&(&1 == "" or MapSet.member?(known, String.downcase(&1))))
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp put_if(map, _key, v) when v in [nil, ""], do: map
  defp put_if(map, key, v), do: Map.put(map, key, v)

  defp put_spoken_date(params, nil, _today), do: params

  defp put_spoken_date(params, iso, today) do
    with {:ok, date} <- Date.from_iso8601(iso), true <- Date.compare(date, today) != :gt do
      iso = Date.to_iso8601(date)
      chip? = iso in Enum.map(date_chips(today), &elem(&1, 0))

      Map.merge(params, %{
        "date" => iso,
        "date_chip" => if(chip?, do: iso),
        "date_typed" => if(chip?, do: "", else: iso)
      })
    else
      _ -> params
    end
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
    |> then(fn socket ->
      days = Training.logged_days(book.id)
      assign(socket, :timeline, Timeline.build(book, days, socket.assigns.progress.stage, today))
    end)
    |> then(fn socket ->
      %{progress: progress, issues: issues, gated: gated} = socket.assigns
      assign(socket, :plan, Training.today_plan(progress.stage, sessions, issues, gated, today))
    end)
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

  def goal_countdown(%Goal{target_date: d}, today), do: countdown(Date.diff(d, today))

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
