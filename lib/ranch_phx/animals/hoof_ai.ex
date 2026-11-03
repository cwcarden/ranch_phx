defmodule RanchPhx.Animals.HoofAI do
  @moduledoc """
  The TrAIner's notes for the farrier from a horse's hoof measurements: what changed,
  how left and right compare, how the hoof-pastern axis looks, and what to ask about.
  Sends the numbers and the newest marked-up photos (one per foot).
  """
  alias RanchPhx.Training.Coach
  alias RanchPhx.Animals.Hooves

  @system """
  You help a horse owner get ready to talk with their farrier. You get hoof angle
  measurements the owner took from photos (toe angle to the ground, pastern angle,
  and the hoof-pastern axis), per foot and over time, and the newest marked-up photo
  of each foot, with the lines the owner placed drawn on it.

  Write short, plain notes the owner can text to the farrier:
  - One sentence on where things stand.
  - Then lines starting with "- " covering, only where there's something to say:
    changes since earlier measurements; whether the fronts match each other and the
    hinds match each other; any foot where the hoof and pastern don't line up; and
    anything in the photos worth a look (for example, the lines don't follow the hoof
    wall well, the photo isn't level, flares or a long toe).
  - End with one or two questions to ask the farrier.
  - Photo angles are rough: a few degrees off is normal if the camera wasn't level or
    square. Say so when a difference is that small.
  - Never diagnose or prescribe trimming or shoeing. That's the farrier's and vet's
    call. Under 180 words. No headings. Use **bold** sparingly.
  """

  def notes(animal, measurements, %Date{} = today) do
    cond do
      not Coach.configured?() ->
        {:error, :no_api_key}

      measurements == [] ->
        {:error, :empty}

      true ->
        latest = Hooves.latest(measurements)

        data = %{
          horse: %{
            name: animal.name,
            born: animal.birth_date && Date.to_iso8601(animal.birth_date),
            breed: animal.breed
          },
          today: Date.to_iso8601(today),
          measurements:
            Enum.map(measurements, fn m ->
              %{
                foot: Hooves.foot_name(m.foot),
                date: Date.to_iso8601(m.date),
                toe_angle: m.toe,
                pastern_angle: m.pastern,
                axis: Hooves.axis_text(m.axis),
                note: m.note
              }
            end)
        }

        photos =
          for {code, _} <- Hooves.feet(),
              m = latest[code],
              m && m.photo,
              bin = read_photo(m.photo),
              bin != nil do
            [
              %{type: "text", text: "Newest #{Hooves.foot_name(code)} photo (#{m.date}):"},
              %{
                type: "image",
                source: %{type: "base64", media_type: "image/jpeg", data: Base.encode64(bin)}
              }
            ]
          end
          |> List.flatten()

        body = %{
          model: Coach.model_name(),
          max_tokens: 1200,
          system: @system,
          messages: [
            %{
              role: "user",
              content:
                [%{type: "text", text: "Measurements (JSON):\n" <> Jason.encode!(data)}] ++ photos
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

  # Photos are under priv/static/uploads; only read our own hoof photos.
  defp read_photo("/uploads/animals/" <> _ = url) do
    if String.contains?(url, "/hooves/") and not String.contains?(url, "..") do
      RanchPhx.Storage.read(url)
    end
  end

  defp read_photo(_), do: nil

  # ── First guess at the dots ──

  @place_system """
  You place measuring dots on a photo of a horse's hoof, for an owner who will check
  each dot and drag any that are off. Give each point as a fraction of the image width
  (x, 0 = left) and height (y, 0 = top). Be precise: put each dot exactly on the edge
  described, not near it.
  """

  @side """
  The photo is the foot from the side, camera at ground level.
  - ground: two points on the ground surface the hoof stands on: first under the heel,
    then just in front of the toe. They set the ground line.
  - wall: two points on the front of the hoof wall (the toe): first at the coronary band
    (the hairline at the top of the toe), then where the toe wall meets the ground.
    Follow the straight part of the wall; ignore a flare or dish near the ground.
  - pastern: two points on the front surface of the pastern: first at the front of the
    fetlock joint, then at the front of the pastern just above the hairline. Empty if the
    pastern isn't in the photo.
  """

  @sole """
  The photo is the bottom of the foot (sole up), picked up and seen square on.
  - toe: one point at the center of the toe, on the outside edge of the hoof wall, in
    line with the frog's center groove.
  - heels: two points at the heel buttresses, the back corner of the wall on each side
    where the wall turns forward into the bar. Not on the bars, frog or heel bulbs.
  - widest: two points on the outside edge of the wall on each side at the widest part
    of the foot, square across the foot.
  - frog: one point at the tip (apex) of the frog, toward the toe. Null if unclear.
  """

  @doc "Where the hoof dots go, as fractions of the image. `{:ok, %{points:, note:}}`."
  def place(image_b64, view) when is_binary(image_b64) and view in ["side", "sole"] do
    cond do
      not Coach.configured?() ->
        {:error, :no_api_key}

      byte_size(image_b64) > 3_000_000 ->
        {:error, :too_big}

      true ->
        body = %{
          model: Coach.model_name(),
          max_tokens: 1200,
          system:
            @place_system <>
              if(view == "side", do: @side, else: @sole) <>
              "\nIf the photo isn't of a hoof from this angle, or a point is hidden or too unclear, say so in note (one or two short sentences) and leave it empty or null. Always answer by calling place_dots.",
          tools: [place_tool(view)],
          messages: [
            %{
              role: "user",
              content: [
                %{
                  type: "image",
                  source: %{type: "base64", media_type: "image/jpeg", data: image_b64}
                },
                %{type: "text", text: "Place the dots on this hoof."}
              ]
            }
          ]
        }

        with {:ok, resp} <- Coach.api_request(body) do
          case Enum.find(resp["content"] || [], &(&1["type"] == "tool_use")) do
            %{"input" => input} -> {:ok, clean(input, view)}
            _ -> {:error, :no_answer}
          end
        end
    end
  end

  def place(_, _), do: {:error, :bad_view}

  defp keys("side"), do: ~w(ground wall pastern)
  defp keys("sole"), do: ~w(toe heels widest frog)

  # Points as {x, y} in 0..1, pairs as lists; anything else dropped.
  defp clean(input, view) do
    pt = fn
      %{"x" => x, "y" => y}
      when is_number(x) and is_number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 ->
        %{x: x, y: y}

      _ ->
        nil
    end

    points =
      for key <- keys(view), into: %{} do
        {key,
         case input[key] do
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

  defp place_tool(view) do
    props =
      case view do
        "side" ->
          %{
            ground: pair("Ground under the heel, then ground in front of the toe."),
            wall: pair("Toe at the hairline, then where the toe meets the ground."),
            pastern:
              pair(
                "Front of the fetlock, then front of the pastern at the hairline. Empty if not visible."
              )
          }

        "sole" ->
          %{
            toe: maybe_point(),
            heels: pair("The two heel buttresses."),
            widest: pair("Outside of the wall on each side at the widest part."),
            frog: maybe_point()
          }
      end
      |> Map.put(:note, %{
        type: ["string", "null"],
        description: "Short note on photo problems, or null."
      })

    %{
      name: "place_dots",
      description: "Place the measuring dots on the hoof photo.",
      strict: true,
      input_schema: %{
        type: "object",
        properties: props,
        required: props |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
        additionalProperties: false
      }
    }
  end
end
