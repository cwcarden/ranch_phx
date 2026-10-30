defmodule RanchPhxWeb.VoiceLogController do
  @moduledoc """
  Where the "Ranch log" Siri Shortcut sends what was said:

      POST /api/voice-log
      Authorization: Bearer rk_…
      {"text": "Dewormed Asher with Panacur today"}

  Saves it for review in the app (nothing becomes a record until it's checked) and
  answers with a short `message` for Siri to read back.
  """
  use RanchPhxWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias RanchPhx.VoiceNotes

  def create(conn, params) do
    with {:ok, user} <- RanchPhxWeb.SiriAuth.authorize(conn),
         {:ok, message} <- save(user, params["text"]) do
      json(conn, %{ok: true, message: message, review_url: url(~p"/voice")})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(401)
        |> json(%{
          ok: false,
          message: "The ranch app didn't accept this Shortcut's key. Make a new key in the app."
        })

      {:error, :empty} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, message: "I didn't catch anything to log."})
    end
  end

  # Routine things (today's dose, a weight) are saved right away; the rest waits for review.
  defp save(user, text) do
    text = text |> to_string() |> String.trim()
    animals = RanchPhx.Repo.all(from a in RanchPhx.Animals.Animal, where: a.owned == true)
    named = VoiceNotes.match_animals(text, animals)

    case text != "" && RanchPhx.VoiceQuick.try_quick(user, text, named, RanchPhx.LocalTime.today()) do
      {:ok, message} ->
        VoiceNotes.broadcast_changed()
        {:ok, message}

      _ ->
        with {:ok, notes} <- VoiceNotes.create_from_text(user, text), do: {:ok, reply(notes)}
    end
  end

  defp reply(notes) do
    case notes |> Enum.map(& &1.animal) |> Enum.reject(&is_nil/1) |> Enum.map(&RanchPhx.Animals.Animal.display_name/1) do
      [] ->
        "Saved. Pick the animal when you review it in the ranch app."

      [name] ->
        "Saved for #{name}. It's waiting for you to check in the ranch app."

      names ->
        "Saved for #{Enum.join(names, " and ")}. They're waiting for you to check in the ranch app."
    end
  end
end
