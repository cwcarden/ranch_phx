defmodule RanchPhx.Training.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "training_sessions" do
    belongs_to :book, RanchPhx.Training.Book

    # Generated when the log form opens, so a re-sent form updates the same row.
    field :client_id, Ecto.UUID
    field :date, :date
    field :session_type, :string
    field :minutes, :integer
    field :tags, {:array, :string}, default: []
    field :note, :string
    field :source, :string, default: "typed"

    timestamps()
  end

  @types [
    {"handling", "Handling"},
    {"groundwork", "Groundwork"},
    {"flag", "Flag / sacking"},
    {"feet", "Feet"},
    {"trailer", "Trailer"},
    {"ponying", "Ponying"},
    {"saddling", "Saddling"},
    {"ground_driving", "Ground driving"},
    {"riding", "Riding"},
    {"cattle", "Cattle"},
    {"other", "Other"}
  ]

  @tags [
    {"good", "Good"},
    {"quiet", "Quiet"},
    {"distracted", "Distracted"},
    {"spooky", "Spooky"},
    {"pushy", "Pushy"},
    {"sticky_left", "Sticky left"},
    {"sticky_right", "Sticky right"},
    {"sore", "Sore"}
  ]

  def types, do: @types
  def tags, do: @tags

  def type_label(slug), do: label(@types, slug)
  def tag_label(slug), do: label(@tags, slug)

  defp label(list, slug) do
    case List.keyfind(list, slug, 0) do
      {_, label} -> label
      nil -> slug
    end
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:book_id, :client_id, :date, :session_type, :minutes, :tags, :note, :source])
    |> update_change(:tags, fn tags -> tags |> Enum.reject(&(&1 == "")) |> Enum.uniq() end)
    |> validate_required([:book_id, :client_id, :date, :session_type])
    |> validate_inclusion(:session_type, Enum.map(@types, &elem(&1, 0)))
    |> validate_subset(:tags, Enum.map(@tags, &elem(&1, 0)))
    |> validate_number(:minutes, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_inclusion(:source, ~w(typed voice))
  end
end
