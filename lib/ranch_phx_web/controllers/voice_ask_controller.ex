defmodule RanchPhxWeb.VoiceAskController do
  @moduledoc """
  Where the "Ranch ask" Siri Shortcut sends a question:

      POST /api/voice-ask
      Authorization: Bearer rk_…
      {"text": "What were yesterday's training notes for Asher?"}

  Answers with a short `message` for Siri to read aloud. Nothing is changed.
  """
  use RanchPhxWeb, :controller
  alias RanchPhx.RanchAsk
  alias RanchPhxWeb.SiriAuth

  def create(conn, params) do
    with {:ok, user} <- SiriAuth.authorize(conn),
         {:ok, text} <- RanchAsk.answer(params["text"], RanchPhx.LocalTime.today(), user.id) do
      json(conn, %{ok: true, message: text})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(401)
        |> json(%{ok: false, message: "The ranch app didn't accept this Shortcut's key. Make a new key in the app."})

      {:error, :empty} ->
        conn |> put_status(422) |> json(%{ok: false, message: RanchAsk.error_message(:empty)})

      {:error, reason} ->
        # Siri still says something useful rather than going quiet.
        json(conn, %{ok: false, message: RanchAsk.error_message(reason)})
    end
  end
end
