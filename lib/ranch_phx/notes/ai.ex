defmodule RanchPhx.Notes.AI do
  @moduledoc "Reads the handwriting on a note page into text, so it can be searched."
  alias RanchPhx.Training.Coach

  @system """
  You transcribe a rancher's handwritten note page (about a horse, dog or cattle) into
  plain text. Copy what's written, in order, keeping the line breaks and lists.
  - Don't add, summarize, correct facts or explain.
  - Fix only obvious spelling slips. Keep numbers, doses, dates and names exactly.
  - A word you can't read: your best guess followed by [?].
  - Drawings or arrows: a short note in brackets, e.g. [sketch of left front hoof].
  - A blank page: answer exactly (blank).
  Answer with the text only.
  """

  def transcribe(png, animal_name) when is_binary(png) do
    if not Coach.configured?() do
      {:error, :no_api_key}
    else
      body = %{
        model: Coach.model_name(),
        max_tokens: 3000,
        system: @system,
        messages: [
          %{
            role: "user",
            content: [
              %{
                type: "image",
                source: %{type: "base64", media_type: "image/png", data: Base.encode64(png)}
              },
              %{type: "text", text: "A note page about #{animal_name}. Transcribe it."}
            ]
          }
        ]
      }

      with {:ok, resp} <- Coach.api_request(body) do
        case resp["content"] |> List.wrap() |> Enum.filter(&(&1["type"] == "text")) do
          [] ->
            {:error, :empty_answer}

          blocks ->
            text = blocks |> Enum.map_join("\n", & &1["text"]) |> String.trim()
            {:ok, if(text == "(blank)", do: "", else: text)}
        end
      end
    end
  end
end
