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
      path = Path.join(Application.app_dir(:ranch_phx, "priv/static"), url)

      case File.read(path) do
        {:ok, bin} -> bin
        _ -> nil
      end
    end
  end

  defp read_photo(_), do: nil
end
