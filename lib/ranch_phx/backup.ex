defmodule RanchPhx.Backup do
  @moduledoc """
  Off-site backup to Cloudflare R2, nightly and on demand:

    1. The database, as a `pg_dump` file (`db/ranch-YYYY-MM-DD.dump`). Keeps the last
       14 nights plus one a month for a year.
    2. Documents (papers, Coggins, registrations), then photos and everything else under
       uploads (`uploads/...`). A file is sent only when R2 doesn't already have it at
       that size, so each photo goes up once. Nothing is ever deleted from the backup
       when it's deleted in the app.
  """
  import Ecto.Query
  require Logger
  alias RanchPhx.Repo
  alias RanchPhx.Backup.{R2, Run}

  @free_bytes 10 * 1024 * 1024 * 1024
  def free_bytes, do: @free_bytes

  def configured?, do: R2.config() != nil

  def last_runs(n \\ 10),
    do: Repo.all(from r in Run, order_by: [desc: r.started_at, desc: r.id], limit: ^n)

  def last_ok,
    do: Repo.one(from r in Run, where: r.status == "ok", order_by: [desc: r.started_at], limit: 1)

  @doc "Runs a backup unless one is already going. Returns the finished run."
  def run(trigger \\ "manual") do
    case :global.trans({__MODULE__, self()}, fn -> do_run(trigger) end, [node()], 0) do
      :aborted -> {:error, :busy}
      result -> result
    end
  end

  @doc "After a restart, marks runs left 'running' as interrupted (once per boot)."
  def clean_up_interrupted_once do
    unless :persistent_term.get({__MODULE__, :cleaned}, false) do
      clean_up_interrupted()
      :persistent_term.put({__MODULE__, :cleaned}, true)
    end
  end

  def clean_up_interrupted do
    Repo.update_all(from(r in Run, where: r.status == "running"),
      set: [status: "error", error: "Interrupted (the app restarted)", finished_at: now()]
    )
  end

  defp do_run(trigger) do
    case R2.config() do
      nil ->
        {:error, :not_configured}

      c ->
        run = Repo.insert!(%Run{trigger: trigger, status: "running", started_at: now()})

        result =
          try do
            steps(c)
          rescue
            e -> {:error, Exception.message(e), %{}}
          end

        {status, error, stats} =
          case result do
            {:ok, stats} -> {"ok", nil, stats}
            {:error, msg, stats} -> {"error", msg, stats}
          end

        if error, do: Logger.error("Backup failed: #{error}")

        run
        |> Ecto.Changeset.change(
          Map.merge(stats, %{status: status, error: error, finished_at: now()})
        )
        |> Repo.update!()
        |> then(&{:ok, &1})
    end
  end

  defp steps(c) do
    with {:ok, remote} <- R2.list(c) do
      stats = %{files_uploaded: 0, bytes_uploaded: 0}

      # Database first, then documents, then the rest.
      {db_result, stats} = backup_db(c, remote, stats)
      {files_result, stats} = backup_files(c, remote, stats)

      {remote_files, remote_bytes} =
        case R2.list(c) do
          {:ok, after_run} -> {map_size(after_run), after_run |> Map.values() |> Enum.sum()}
          _ -> {nil, nil}
        end

      stats = Map.merge(stats, %{remote_files: remote_files, remote_bytes: remote_bytes})

      case Enum.reject([db_result, files_result], &(&1 == :ok)) do
        [] -> {:ok, stats}
        errors -> {:error, errors |> Enum.map(fn {:error, m} -> m end) |> Enum.join("; "), stats}
      end
    else
      {:error, msg} -> {:error, msg, %{}}
    end
  end

  # ── Database ────────────────────────────────────────────────────────────────

  defp backup_db(c, remote, stats) do
    tmp = Path.join(System.tmp_dir!(), "ranch-#{System.unique_integer([:positive])}.dump")

    try do
      with :ok <- dump(tmp),
           {:ok, body} <- File.read(tmp),
           key = "db/ranch-#{RanchPhx.LocalTime.today()}.dump",
           :ok <- R2.put(c, key, body) do
        prune_dumps(c, Map.put(remote, key, byte_size(body)))
        n = byte_size(body)

        {:ok,
         Map.merge(stats, %{
           files_uploaded: stats.files_uploaded + 1,
           bytes_uploaded: stats.bytes_uploaded + n,
           db_bytes: n
         })}
      else
        {:error, msg} -> {{:error, "Database: #{msg}"}, stats}
      end
    after
      File.rm(tmp)
    end
  end

  defp dump(path) do
    cfg = Repo.config()
    url = cfg[:url] && URI.parse(cfg[:url])
    {user, pass} = userinfo(url, cfg)

    args =
      ["--format=custom", "--no-owner", "--no-privileges", "--file", path] ++
        ["--host", (url && url.host) || cfg[:hostname] || "localhost"] ++
        ["--port", to_string((url && url.port) || cfg[:port] || 5432)] ++
        ["--username", user || "postgres"] ++
        [(url && String.trim_leading(url.path || "", "/")) || cfg[:database]]

    case System.find_executable("pg_dump") do
      nil ->
        {:error, "pg_dump isn't installed on the server"}

      exe ->
        case System.cmd(exe, args, env: [{"PGPASSWORD", pass || ""}], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {out, code} -> {:error, "pg_dump exited #{code}: #{String.slice(out, 0, 300)}"}
        end
    end
  end

  defp userinfo(%URI{userinfo: info}, _cfg) when is_binary(info) do
    case String.split(info, ":", parts: 2) do
      [u, p] -> {URI.decode(u), URI.decode(p)}
      [u] -> {URI.decode(u), nil}
    end
  end

  defp userinfo(_, cfg), do: {cfg[:username], cfg[:password]}

  @doc "Which nightly database copies to drop: keeps the newest 14, plus the newest of each month for a year."
  def dumps_to_drop(keys) do
    dated =
      for k <- keys,
          [_, d] <- [Regex.run(~r"^db/ranch-(\d{4}-\d{2}-\d{2})\.dump$", k)],
          {:ok, date} <- [Date.from_iso8601(d)],
          do: {k, date}

    sorted = Enum.sort_by(dated, &elem(&1, 1), {:desc, Date})
    recent = sorted |> Enum.take(14) |> Enum.map(&elem(&1, 0))

    monthly =
      sorted
      |> Enum.uniq_by(fn {_, d} -> {d.year, d.month} end)
      |> Enum.take(12)
      |> Enum.map(&elem(&1, 0))

    keep = MapSet.new(recent ++ monthly)
    for {k, _} <- dated, not MapSet.member?(keep, k), do: k
  end

  defp prune_dumps(c, remote),
    do: remote |> Map.keys() |> dumps_to_drop() |> Enum.each(&R2.delete(c, &1))

  # ── Uploaded files ──────────────────────────────────────────────────────────

  def uploads_dir,
    do:
      Application.get_env(:ranch_phx, :backup_uploads_dir) ||
        Application.app_dir(:ranch_phx, "priv/static/uploads")

  @doc "Local uploaded files as `[{relative_path, size}]`, documents first."
  def local_files do
    dir = uploads_dir()

    Path.join(dir, "**")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case File.stat(path) do
        {:ok, %{type: :regular, size: size}} -> [{Path.relative_to(path, dir), size}]
        _ -> []
      end
    end)
    |> Enum.sort_by(fn {rel, _} -> {not String.contains?(rel, "/documents/"), rel} end)
  end

  defp backup_files(c, remote, stats) do
    dir = uploads_dir()

    {errors, stats} =
      Enum.reduce(local_files(), {[], stats}, fn {rel, size}, {errors, stats} ->
        key = "uploads/" <> rel

        if Map.get(remote, key) == size do
          {errors, stats}
        else
          with {:ok, body} <- File.read(Path.join(dir, rel)),
               :ok <- R2.put(c, key, body, MIME.from_path(rel)) do
            {errors,
             %{
               stats
               | files_uploaded: stats.files_uploaded + 1,
                 bytes_uploaded: stats.bytes_uploaded + size
             }}
          else
            {:error, msg} -> {[rel <> ": " <> to_string(msg) | errors], stats}
          end
        end
      end)

    case errors do
      [] -> {:ok, stats}
      _ -> {{:error, "#{length(errors)} file(s) didn't copy (#{List.last(errors)})"}, stats}
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
