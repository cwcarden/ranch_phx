defmodule RanchPhx.Conformations.AI do
  @moduledoc """
  Claude's two jobs on the conformation page:

    * `place/1`: a first guess at where each landmark is on the photo, for the owner to
      check and drag into place.
    * `review/3`: after the owner has adjusted the dots and saved, what's good and what to
      watch, from the marked-up photo and the numbers worked out from those dots.
  """
  alias RanchPhx.Training.Coach
  alias RanchPhx.Conformations

  @landmarks ~w(withers shoulder hip buttock croup poll ground)

  @place_system """
  You mark conformation landmarks on a side photo of a horse, for a rancher who will
  check each dot and drag any that are off. Give each point as a fraction of the image
  width (x, 0 = left) and height (y, 0 = top).

  - withers: the top of the withers, the highest point of the back above the shoulders.
  - shoulder: two points. First the top of the shoulder blade (a few inches below and
    behind the top of the withers, at the upper end of the blade's ridge), then the point
    of the shoulder (the bony front of the chest, where the neck meets the front leg).
  - hip: the point of the hip, the bony knob at the front top of the hindquarters.
  - buttock: the point of the buttock, the rearmost point of the hindquarters.
  - croup: the highest point of the croup (top of the rump).
  - poll: the top of the head between the ears.
  - ground: two points on the ground line, under the front hooves and under the hind
    hooves.

  If the horse isn't standing broadside, a landmark is hidden, or the photo is too
  unclear, say so in note and leave that point null. Never invent a horse. Always answer
  by calling place_landmarks.
  """

  @review_system """
  You help a rancher (a former colt starter raising a reining / cow horse prospect)
  evaluate a horse's conformation from a side photo. The photo has dots and lines the
  owner placed or corrected by hand; the numbers were worked out from those dots. Trust
  the owner's dots; if one still looks clearly off on the photo, say which.

  Write plain, practical notes in exactly four short parts, each a bold heading on its
  own line followed by 2–4 bullets:

  **What's good**
  **What to watch**
  **Best suited for**
  **Photo and dots check**

  - Best suited for: rank the top two or three uses from reining, cutting, working cow
    horse, heading, heeling, ranch riding / versatility, barrel racing, halter, western
    pleasure, trail. Say why in a few words each, tied to his build (shoulder, hip, how
    he's put together uphill or not, length, neck). Conformation is only part of it;
    mind, breeding and training matter as much.
  - Tie points to the numbers and to what they mean for a riding / performance horse
    (stride, carrying weight behind, stop and turn, soundness over time).
  - Account for age when known: young horses are often croup-high and change as they grow.
  - Conformation is a guide, not a verdict. No diagnoses; a vet should check soundness
    for a purchase. Under 260 words. No other headings.
  """

  @doc "Where the landmarks are, as fractions of the image. `{:ok, %{points:, note:}}`."
  def place(image_b64) when is_binary(image_b64) do
    cond do
      not Coach.configured?() ->
        {:error, :no_api_key}

      byte_size(image_b64) > 3_000_000 ->
        {:error, :too_big}

      true ->
        body = %{
          model: Coach.model_name(),
          max_tokens: 1500,
          system: @place_system,
          tools: [place_tool()],
          messages: [
            %{
              role: "user",
              content: [
                %{
                  type: "image",
                  source: %{type: "base64", media_type: "image/jpeg", data: image_b64}
                },
                %{type: "text", text: "Mark the landmarks on this horse."}
              ]
            }
          ]
        }

        with {:ok, resp} <- Coach.api_request(body) do
          case Enum.find(resp["content"] || [], &(&1["type"] == "tool_use")) do
            %{"input" => input} -> {:ok, clean(input)}
            _ -> {:error, :no_answer}
          end
        end
    end
  end

  # Points as {x, y} in 0..1, pairs as lists; anything else dropped.
  defp clean(input) do
    pt = fn
      %{"x" => x, "y" => y}
      when is_number(x) and is_number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 ->
        %{x: x, y: y}

      _ ->
        nil
    end

    points =
      for key <- @landmarks, into: %{} do
        v = input[key]

        {key,
         case v do
           list when is_list(list) -> list |> Enum.map(pt) |> Enum.reject(&is_nil/1)
           other -> pt.(other)
         end}
      end

    %{points: points, note: input["note"]}
  end

  defp point,
    do: %{
      type: "object",
      properties: %{x: %{type: "number"}, y: %{type: "number"}},
      required: ["x", "y"],
      additionalProperties: false
    }

  defp maybe_point, do: %{anyOf: [point(), %{type: "null"}]}
  defp pair(desc), do: %{type: "array", items: point(), description: desc}

  defp place_tool do
    props = %{
      withers: maybe_point(),
      shoulder: pair("Top of the shoulder blade, then point of the shoulder. Empty if unclear."),
      hip: maybe_point(),
      buttock: maybe_point(),
      croup: maybe_point(),
      poll: maybe_point(),
      ground: pair("Ground under the front hooves, then under the hind hooves."),
      note: %{type: ["string", "null"], description: "Short note on photo problems, or null."}
    }

    %{
      name: "place_landmarks",
      description: "Place the conformation landmarks on the photo.",
      strict: true,
      input_schema: %{
        type: "object",
        properties: props,
        required: props |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
        additionalProperties: false
      }
    }
  end

  @doc "What's good and what to watch, from the adjusted dots. `{:ok, text}`."
  def review(evaluation, age_months, %Date{} = today) do
    if not Coach.configured?() do
      {:error, :no_api_key}
    else
      data = %{
        who: Conformations.who(evaluation),
        prospect: Conformations.prospect?(evaluation),
        age_months: age_months,
        today: Date.to_iso8601(today),
        photo_date: Date.to_iso8601(evaluation.date),
        shoulder_angle: evaluation.shoulder,
        hip_angle: evaluation.hip,
        uphill_percent: evaluation.uphill,
        body_length_over_height: evaluation.length_ratio,
        thirds_shoulder_back_hip_percent: evaluation.thirds,
        neck_over_back: evaluation.neck_ratio,
        owner_note: evaluation.note,
        what_the_app_says: Enum.map(Conformations.summary(evaluation, age_months), &elem(&1, 1))
      }

      photo =
        case read_photo(evaluation.photo_url) do
          nil ->
            []

          bin ->
            [
              %{
                type: "image",
                source: %{type: "base64", media_type: "image/jpeg", data: Base.encode64(bin)}
              }
            ]
        end

      body = %{
        model: Coach.model_name(),
        max_tokens: 1200,
        system: @review_system,
        messages: [
          %{
            role: "user",
            content:
              photo ++
                [
                  %{
                    type: "text",
                    text: "The numbers from the owner's dots (JSON):\n" <> Jason.encode!(data)
                  }
                ]
          }
        ]
      }

      with {:ok, resp} <- Coach.api_request(body) do
        case resp["content"] |> List.wrap() |> Enum.filter(&(&1["type"] == "text")) do
          [] -> {:error, :empty_answer}
          blocks -> {:ok, blocks |> Enum.map_join("\n\n", & &1["text"]) |> String.trim()}
        end
      end
    end
  end

  @ask_system """
  You answer a rancher's questions about one horse's conformation (a former colt
  starter, raising a reining / cow horse prospect). You have the side photo with the
  owner's corrected dots and lines, the numbers from those dots, the app's own read of
  them, your earlier review, and the conversation so far. Answer the question directly
  and practically, in a few short sentences or bullets, tied to this horse's build.
  Say when a photo can't tell you something (soundness, feet, mind, movement) and what
  to look at in person or ask a vet. No diagnoses. Under 180 words.
  """

  @doc "Answers a question about this evaluation. `history` is [%{\"q\" => , \"a\" => }]."
  def ask(evaluation, age_months, question, %Date{} = today) do
    question = question |> to_string() |> String.trim() |> String.slice(0, 1000)

    cond do
      question == "" ->
        {:error, :empty}

      not Coach.configured?() ->
        {:error, :no_api_key}

      true ->
        context = %{
          who: Conformations.who(evaluation),
          prospect: Conformations.prospect?(evaluation),
          age_months: age_months,
          today: Date.to_iso8601(today),
          shoulder_angle: evaluation.shoulder,
          hip_angle: evaluation.hip,
          uphill_percent: evaluation.uphill,
          body_length_over_height: evaluation.length_ratio,
          thirds_shoulder_back_hip_percent: evaluation.thirds,
          neck_over_back: evaluation.neck_ratio,
          owner_note: evaluation.note,
          what_the_app_says:
            Enum.map(Conformations.summary(evaluation, age_months), &elem(&1, 1)),
          your_review: evaluation.ai_notes
        }

        photo =
          case read_photo(evaluation.photo_url) do
            nil ->
              []

            bin ->
              [
                %{
                  type: "image",
                  source: %{type: "base64", media_type: "image/jpeg", data: Base.encode64(bin)}
                }
              ]
          end

        # The last few exchanges, as turns.
        history =
          (evaluation.ai_chat || [])
          |> Enum.take(-6)
          |> Enum.flat_map(fn t ->
            [
              %{role: "user", content: to_string(t["q"])},
              %{role: "assistant", content: to_string(t["a"])}
            ]
          end)

        first = %{
          role: "user",
          content:
            photo ++
              [%{type: "text", text: "About this horse (JSON):\n" <> Jason.encode!(context)}]
        }

        ack = %{role: "assistant", content: "Got it. What would you like to know?"}

        body = %{
          model: Coach.model_name(),
          max_tokens: 900,
          system: @ask_system,
          messages: [first, ack] ++ history ++ [%{role: "user", content: question}]
        }

        with {:ok, resp} <- Coach.api_request(body) do
          case resp["content"] |> List.wrap() |> Enum.filter(&(&1["type"] == "text")) do
            [] -> {:error, :empty_answer}
            blocks -> {:ok, blocks |> Enum.map_join("\n\n", & &1["text"]) |> String.trim()}
          end
        end
    end
  end

  defp read_photo("/uploads/conformation/" <> _ = url) do
    if not String.contains?(url, "..") do
      case File.read(Path.join(Application.app_dir(:ranch_phx, "priv/static"), url)) do
        {:ok, bin} -> bin
        _ -> nil
      end
    end
  end

  defp read_photo(_), do: nil
end
