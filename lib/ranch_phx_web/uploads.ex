defmodule RanchPhxWeb.Uploads do
  @moduledoc """
  Saves uploaded photos under priv/static/uploads, the same way the animal
  pages do. iPhone HEIC/HEIF photos are converted to JPEG with heif-convert.
  """
  require Logger

  @uploads_dir Application.app_dir(:ranch_phx, "priv/static/uploads")

  @image_types ~w(.jpg .jpeg .png .webp .gif .heic .heif)

  def image_types, do: @image_types

  @doc "Copy the temp upload to uploads/<subdir>/ and return its URL, or nil on failure."
  def save_image(tmp_path, client_name, subdir) do
    dir = Path.join(@uploads_dir, subdir)
    File.mkdir_p!(dir)

    orig_ext = client_name |> Path.extname() |> String.downcase()
    heic? = orig_ext in [".heic", ".heif"]
    ext = if heic?, do: ".jpg", else: orig_ext
    name = "#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}#{ext}"
    dest = Path.join(dir, name)

    ok? =
      if heic? do
        heif = System.find_executable("heif-convert") || "/usr/bin/heif-convert"

        case System.cmd(heif, [tmp_path, dest], stderr_to_stdout: true) do
          {_, 0} ->
            true

          {out, code} ->
            Logger.error("heif-convert failed (#{code}): #{out}")
            false
        end
      else
        File.cp!(tmp_path, dest)
        true
      end

    if ok?, do: "/uploads/#{subdir}/#{name}"
  rescue
    e in ErlangError ->
      Logger.error("photo upload failed: #{Exception.message(e)}")
      nil
  end

  @doc "Delete a saved training photo file. Ignores anything outside uploads/training/."
  def delete_file("/uploads/training/" <> rest = _url) do
    unless String.contains?(rest, "..") do
      File.rm(Path.join([@uploads_dir, "training", rest]))
    end

    :ok
  end

  def delete_file(_url), do: :ok
end
