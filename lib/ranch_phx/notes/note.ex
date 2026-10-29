defmodule RanchPhx.Notes.Note do
  @moduledoc "One handwritten page about an animal."
  use Ecto.Schema
  import Ecto.Changeset

  @topics ~w(general health training feeding farrier breeding ideas)
  def topics, do: @topics

  schema "animal_notes" do
    belongs_to :animal, RanchPhx.Animals.Animal
    field :date, :date
    field :topic, :string, default: "general"
    field :title, :string
    field :page_url, :string
    field :strokes_url, :string
    field :text, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(n, attrs) do
    n
    |> cast(attrs, [:animal_id, :date, :topic, :title, :page_url, :strokes_url, :text])
    |> validate_required([:animal_id, :date, :topic])
    |> validate_inclusion(:topic, @topics)
    |> validate_length(:title, max: 120)
    |> validate_length(:text, max: 20_000)
  end
end
