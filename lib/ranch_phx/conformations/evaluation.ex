defmodule RanchPhx.Conformations.Evaluation do
  @moduledoc "One conformation evaluation: a marked-up side photo and the numbers from it."
  use Ecto.Schema
  import Ecto.Changeset

  schema "conformations" do
    belongs_to :animal, RanchPhx.Animals.Animal
    field :name, :string
    field :note, :string
    field :date, :date
    field :photo_url, :string
    field :original_url, :string
    field :points, :map, default: %{}
    field :shoulder, :float
    field :hip, :float
    field :uphill, :float
    field :length_ratio, :float
    field :neck_ratio, :float
    field :thirds, {:array, :integer}
    field :ai_notes, :string
    field :ai_chat, {:array, :map}, default: []
    timestamps(type: :utc_datetime)
  end

  @fields ~w(animal_id name note date photo_url original_url points shoulder hip uphill
             length_ratio neck_ratio thirds ai_notes ai_chat)a

  def changeset(e, attrs) do
    e
    |> cast(attrs, @fields)
    |> validate_required([:date])
    |> validate_length(:name, max: 120)
    |> validate_length(:note, max: 1000)
    |> validate_number(:shoulder, greater_than: 0, less_than: 90)
    |> validate_number(:hip, greater_than: 0, less_than: 90)
    |> validate_number(:uphill, greater_than: -50, less_than: 50)
    |> validate_number(:length_ratio, greater_than: 0, less_than: 5)
    |> validate_number(:neck_ratio, greater_than: 0, less_than: 5)
    |> check_who()
  end

  # Either one of the ranch's animals, or a prospect with a name.
  defp check_who(cs) do
    if get_field(cs, :animal_id) || String.trim(get_field(cs, :name) || "") != "",
      do: cs,
      else: add_error(cs, :name, "Give the prospect a name")
  end
end
