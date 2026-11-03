defmodule RanchPhx.FeedPlans.FeedPlan do
  @moduledoc """
  How to feed one animal while the owner is away: a few titled sections (morning feed,
  hay, contacts…) of plain text. It can be shared by a secret link that shows the
  latest version and works only while sharing is on.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "feed_plans" do
    belongs_to :animal, RanchPhx.Animals.Animal
    field :sections, {:array, :map}, default: []
    field :share_token, :string
    field :share_on, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:sections, :share_on])
    |> update_change(:sections, &clean_sections/1)
    |> validate_length(:sections, max: 20)
  end

  @doc "Sections as `%{\"title\" => ..., \"body\" => ...}`, trimmed; fully blank ones dropped."
  def clean_sections(sections) when is_list(sections) do
    sections
    |> Enum.map(fn s ->
      %{
        "title" => s |> get("title") |> String.slice(0, 80),
        "body" => s |> get("body") |> String.slice(0, 3000)
      }
    end)
    |> Enum.reject(&(&1["title"] == "" and &1["body"] == ""))
  end

  def clean_sections(_), do: []

  defp get(s, k),
    do:
      (Map.get(s, k) || Map.get(s, String.to_existing_atom(k)) || "")
      |> to_string()
      |> String.trim()
end
