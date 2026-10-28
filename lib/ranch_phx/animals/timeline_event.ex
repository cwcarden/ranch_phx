defmodule RanchPhx.Animals.TimelineEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "timeline_events" do
    belongs_to :animal, RanchPhx.Animals.Animal

    field :event_type,  :string
    field :title,       :string
    field :description, :string
    field :event_date,  :date
    field :event_time,  :time
    field :location,    :string
    field :photo_urls,  {:array, :string}, default: []
    field :metadata,    :map, default: %{}

    timestamps()
  end

  @event_types ~w(birth registration purchase sale
                  vet_visit vaccination deworming farrier dental
                  training show branding
                  weight height hoof pregnancy foaling
                  photo_added note retirement death other)

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:animal_id, :event_type, :title, :description, :event_date, :event_time, :location, :photo_urls, :metadata])
    |> validate_required([:animal_id, :title, :event_type])
    |> validate_inclusion(:event_type, @event_types)
  end

  def event_types, do: @event_types

  def type_label("vet_visit"),   do: "Vet Visit"
  def type_label("photo_added"), do: "Photo"
  def type_label(t), do: t |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
end
