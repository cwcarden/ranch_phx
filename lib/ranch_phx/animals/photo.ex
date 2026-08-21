defmodule RanchPhx.Animals.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    belongs_to :animal, RanchPhx.Animals.Animal

    field :url,      :string
    field :caption,  :string
    field :tags,     {:array, :string}, default: []
    field :taken_at, :date
    field :is_cover, :boolean, default: false

    timestamps()
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:animal_id, :url, :caption, :tags, :taken_at, :is_cover])
    |> validate_required([:animal_id, :url])
  end
end
