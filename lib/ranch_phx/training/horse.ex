defmodule RanchPhx.Training.Horse do
  use Ecto.Schema
  import Ecto.Changeset

  # A horse in training. `animal` is set when it's also a ranch animal;
  # outside horses (someone else's horse you're riding) have none.
  schema "training_horses" do
    belongs_to :animal, RanchPhx.Animals.Animal

    field :name, :string
    field :foaled_on, :date
    field :sex, :string
    field :breed, :string
    field :color, :string
    field :owner, :string
    field :photo_url, :string
    field :notes, :string

    has_many :books, RanchPhx.Training.Book

    timestamps()
  end

  def changeset(horse, attrs) do
    horse
    |> cast(attrs, [:animal_id, :name, :foaled_on, :sex, :breed, :color, :owner, :notes])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:animal_id, message: "already has a training profile")
  end

  def photo_changeset(horse, url), do: change(horse, photo_url: url)
end
