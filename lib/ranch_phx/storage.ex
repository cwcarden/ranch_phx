defmodule RanchPhx.Storage do
  @moduledoc """
  Where uploaded files (photos, papers, notes pages) live on disk, served at `/uploads/...`.

  One folder for everything, outside the built release. A deploy rebuilds the release
  from scratch (and deletes the old one), so files must never be kept inside it. The
  folder is the app's own `priv/static/uploads` in the source checkout (on the server,
  `/opt/ranch_phx/priv/static/uploads`), which no build step touches. `UPLOADS_DIR`
  (or `config :ranch_phx, :uploads_dir`) can point it somewhere else.

  Nothing here deletes anything except `rm/1`, which the app calls when you delete a
  photo or paper yourself.
  """
  require Logger
  import Ecto.Query, only: [from: 2]
  alias RanchPhx.Repo

  # The source checkout's uploads folder, fixed when the app is compiled.
  @source_dir Path.expand("../../priv/static/uploads", __DIR__)

  @doc "The uploads folder."
  def root, do: Application.get_env(:ranch_phx, :uploads_dir) || @source_dir

  # Where older versions saved most uploads: the build folder's copy, fixed at compile time.
  @build_dir Application.app_dir(:ranch_phx, "priv/static/uploads")

  @doc "The folder inside a built release that older versions sometimes saved into."
  def release_dir, do: Application.app_dir(:ranch_phx, "priv/static/uploads")

  defp old_dirs, do: Enum.uniq([release_dir(), @build_dir])

  @doc "Absolute path for a `/uploads/...` address (or a path relative to the folder); nil if it isn't one of ours."
  def path("/uploads/" <> rest), do: path(rest)

  def path(rel) when is_binary(rel) do
    if rel != "" and not String.contains?(rel, "..") and not String.starts_with?(rel, "/"),
      do: Path.join(root(), rel)
  end

  def path(_), do: nil

  @doc "The bytes of a `/uploads/...` file (looking in the release too, for files saved there before), or nil."
  def read(url) do
    rel = String.replace_prefix(url, "/uploads/", "")

    with p when is_binary(p) <- path(rel),
         {:ok, bin} <- File.read(p) do
      bin
    else
      _ ->
        if path(rel) do
          Enum.find_value(old_dirs(), fn d ->
            case File.read(Path.join(d, rel)) do
              {:ok, bin} -> bin
              _ -> nil
            end
          end)
        end
    end
  end

  @doc "Saves the file at `tmp` under `subdir` (\"animals/3/photos\") with a random name; returns its `/uploads/...` address."
  def store(tmp, subdir, ext \\ ".jpg") do
    dir = Path.join(root(), subdir)
    File.mkdir_p!(dir)
    name = (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)) <> ext
    File.cp!(tmp, Path.join(dir, name))
    "/uploads/" <> subdir <> "/" <> name
  end

  @doc "Deletes one uploaded file the user deleted in the app."
  def rm(url) do
    case path(url) do
      nil -> :ok
      p -> File.rm(p)
    end
  end

  @doc """
  Copies any file that only exists inside the release (where older versions saved some
  photos) into the uploads folder. Copies only; never overwrites or deletes.
  Returns how many were copied.
  """
  def adopt_release_files do
    to = root()

    old_dirs()
    |> Enum.reject(&(Path.expand(&1) == Path.expand(to) or not File.dir?(&1)))
    |> Enum.map(fn from -> adopt(from, to) end)
    |> Enum.sum()
  rescue
    e ->
      Logger.error("Couldn't copy uploads out of the release: #{Exception.message(e)}")
      0
  end

  defp adopt(from, to) do
    from
    |> files()
    |> Enum.count(fn rel ->
      dest = Path.join(to, rel)

      if File.exists?(dest) do
        false
      else
        File.mkdir_p!(Path.dirname(dest))
        File.cp(Path.join(from, rel), dest) == :ok
      end
    end)
  end

  @doc "Every file under `dir`, as paths relative to it."
  def files(dir) do
    Path.join(dir, "**")
    |> Path.wildcard(match_dot: false)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
  end

  @doc """
  Every `/uploads/...` file the database points at (photos, papers, notes pages, cover
  photos, anything), found by looking through every table.
  """
  def referenced do
    cols =
      Repo.all(
        from c in "columns",
          prefix: "information_schema",
          where:
            c.table_schema == "public" and
              c.data_type in ["text", "character varying", "jsonb", "json", "ARRAY"] and
              c.table_name != "schema_migrations",
          select: {c.table_name, c.column_name}
      )

    cols
    |> Enum.flat_map(fn {table, col} ->
      q = ~s|SELECT "#{col}"::text FROM "#{table}" WHERE "#{col}"::text LIKE '%/uploads/%'|

      case Repo.query(q) do
        {:ok, %{rows: rows}} ->
          Enum.flat_map(rows, fn [v] ->
            Regex.scan(~r{/uploads/[A-Za-z0-9_\-./]+}, v || "") |> List.flatten()
          end)

        _ ->
          []
      end
    end)
    |> Enum.map(&String.trim_trailing(&1, "."))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "The `/uploads/...` files the database points at that aren't on disk."
  def missing do
    Enum.reject(referenced(), fn url ->
      p = path(url)
      p == nil or File.exists?(p)
    end)
  end
end
