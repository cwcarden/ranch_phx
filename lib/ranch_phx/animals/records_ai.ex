defmodule RanchPhx.Animals.RecordsAI do
  @moduledoc """
  Claude on the ranch records side:

    * `summarize/4` – a short, plain read of an animal's records: where things stand,
      what's due, gaps worth checking, anything notable.
    * `draft/5` – turns "gave West Nile and EWT today, dewormed with Quest, farrier
      trimmed yesterday" into record drafts to check before saving.

  Uses the same API key and connection as the TrAIner (`RanchPhx.Training.Coach`).
  """
  alias RanchPhx.Training.Coach
  alias RanchPhx.Animals.CareSchedule

  @summary_system """
  You read a ranch's records for one animal and give the owner a quick, plain summary.

  - Lead with one sentence on where things stand.
  - Then short lines starting with "- " covering, only where there's something to say:
    what's due or overdue (with dates); gaps worth checking (for example no Coggins in the
    last 12 months, no dental in over a year, vaccines with no next-due date); anything
    notable lately (injuries, vet visits, changes); and money spent this year if costs
    are recorded.
  - Use only what's in the records. Never invent dates, products or results. If there's
    too little to say, say so and suggest what to start recording.
  - Never diagnose. Vaccine and deworming schedules vary by area and vet, so suggest
    confirming timing with their vet instead of prescribing one.
  - Under 220 words. No headings, no tables. Use **bold** only for dates that are due.
  """

  @doc "A plain-language summary of `records` (and document titles) for `animal`."
  def summarize(animal, records, documents, %Date{} = today) do
    cond do
      not Coach.configured?() ->
        {:error, :no_api_key}

      true ->
        data = %{
          animal: %{
            name: animal.name,
            kind: animal.kind,
            sex: animal.sex,
            breed: animal.breed,
            born: animal.birth_date && Date.to_iso8601(animal.birth_date)
          },
          records:
            Enum.map(records, fn r ->
              compact(%{
                type: r.record_type,
                category: r.category,
                title: r.title,
                date: Date.to_iso8601(r.date),
                next_due: r.next_due_date && Date.to_iso8601(r.next_due_date),
                person: r.person,
                cost: r.cost && Decimal.to_string(r.cost),
                description: r.description,
                notes: r.notes
              })
            end),
          documents:
            Enum.map(documents, fn d ->
              compact(%{
                title: d.title,
                type: d.doc_type,
                date: d.doc_date && Date.to_iso8601(d.doc_date)
              })
            end)
        }

        body = %{
          model: Coach.model_name(),
          max_tokens: 1500,
          system: @summary_system,
          messages: [
            %{
              role: "user",
              content:
                "Today is #{Date.to_iso8601(today)}. Records (JSON):\n#{Jason.encode!(data)}"
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

  @draft_system """
  You turn what an owner said about care given to an animal (often dictated on a phone)
  into ranch records, one record per thing done.

  - One record per vaccine, treatment or service: "West Nile and EWT" is two records.
  - record_type must be one of the given type slugs; pick the closest.
  - title: short and specific, like "West Nile vaccine" or "Deworming – Quest Plus".
  - date: YYYY-MM-DD if they said a day other than today ("yesterday"), else null.
  - next_due_date: only if they said when it's due next, else null.
  - person, location, cost, description: only if they said them, else null.
    Product names and lot numbers go in description.
  - Never invent anything they didn't say.
  """

  @doc """
  Record drafts from spoken notes. `types` are `%{slug, label, category}` maps for the
  record types that exist. Returns `{:ok, [draft]}` where each draft is a map with string
  keys ready for `Animals.create_record/1` (plus "animal_id" to be added), or `{:error, reason}`.
  """
  def draft(animal, text, %Date{} = today, types) do
    text = text |> to_string() |> String.trim() |> String.slice(0, 3000)

    cond do
      text == "" ->
        {:error, :empty}

      not Coach.configured?() ->
        {:error, :no_api_key}

      true ->
        body = %{
          model: Coach.model_name(),
          max_tokens: 2000,
          system: @draft_system,
          tools: [draft_tool(types)],
          tool_choice: %{type: "tool", name: "add_records"},
          messages: [
            %{
              role: "user",
              content: """
              Today is #{Date.to_iso8601(today)}. Animal: #{animal.name} (#{animal.kind}).
              Record types: #{Jason.encode!(Enum.map(types, &%{slug: &1.slug, label: &1.label}))}

              What they said:
              #{text}
              """
            }
          ]
        }

        with {:ok, resp} <- Coach.api_request(body) do
          case Enum.find(resp["content"] || [], &(&1["type"] == "tool_use")) do
            %{"input" => %{"records" => records}} when is_list(records) ->
              slugs = MapSet.new(types, & &1.slug)

              {:ok,
               records
               |> Enum.filter(&MapSet.member?(slugs, &1["record_type"]))
               |> Enum.map(&to_draft(&1, animal, today))}

            _ ->
              {:error, :empty_answer}
          end
        end
    end
  end

  defp to_draft(r, animal, today) do
    date =
      case r["date"] && Date.from_iso8601(r["date"]) do
        {:ok, d} -> if Date.compare(d, today) == :gt, do: today, else: d
        _ -> today
      end

    {due, suggested?} =
      case r["next_due_date"] && Date.from_iso8601(r["next_due_date"]) do
        {:ok, d} ->
          {d, false}

        _ ->
          d = CareSchedule.suggested_due(animal.kind, r["record_type"], r["title"], date)
          {d, d != nil}
      end

    %{
      "record_type" => r["record_type"],
      "title" => r["title"],
      "date" => Date.to_iso8601(date),
      "next_due_date" => due && Date.to_iso8601(due),
      "due_suggested" => suggested?,
      "person" => r["person"],
      "location" => r["location"],
      "cost" => r["cost"],
      "description" => r["description"]
    }
  end

  defp nullable(type, desc), do: %{type: [type, "null"], description: desc}

  defp draft_tool(types) do
    %{
      name: "add_records",
      description: "Add one record per thing that was done.",
      strict: true,
      input_schema: %{
        type: "object",
        properties: %{
          records: %{
            type: "array",
            items: %{
              type: "object",
              properties: %{
                record_type: %{type: "string", enum: Enum.map(types, & &1.slug)},
                title: %{type: "string", description: "Short and specific."},
                date: nullable("string", "YYYY-MM-DD if not today, else null."),
                next_due_date: nullable("string", "YYYY-MM-DD only if they said, else null."),
                person: nullable("string", "Vet, farrier or whoever did it, or null."),
                location: nullable("string", "Where, or null."),
                cost: nullable("number", "Cost in dollars, or null."),
                description: nullable("string", "Product, dose, lot number, findings, or null.")
              },
              required: ~w(record_type title date next_due_date person location cost description),
              additionalProperties: false
            }
          }
        },
        required: ["records"],
        additionalProperties: false
      }
    }
  end

  defp compact(map), do: Map.reject(map, fn {_k, v} -> v in [nil, "", []] end)
end
