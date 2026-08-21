defmodule RanchPhx.Animals.PedigreeEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pedigree_entries" do
    belongs_to :animal, RanchPhx.Animals.Animal

    field :slot,                :string   # "S", "DS", "SSS", up to 5-6 chars
    field :name,                :string
    field :registration_number, :string
    field :breed,               :string
    field :birth_year,          :integer
    field :color,               :string
    field :sex,                 :string
    field :notes,               :string

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:animal_id, :slot, :name, :registration_number, :breed, :birth_year, :color, :sex, :notes])
    |> validate_required([:animal_id, :slot, :name])
    |> validate_length(:slot, min: 1, max: 6)
    |> validate_format(:slot, ~r/^[SD]+$/)
    |> validate_number(:birth_year, greater_than: 1700, less_than: 2100)
    |> unique_constraint([:animal_id, :slot])
  end

  # "S" → "Sire", "SS" → "Sire's Sire", "DS" → "Dam's Sire", etc.
  def slot_label(slot) do
    slot
    |> String.graphemes()
    |> Enum.map(fn "S" -> "Sire"; "D" -> "Dam" end)
    |> Enum.join("'s ")
  end

  @gen_labels %{1 => "Sire / Dam", 2 => "Grandparents", 3 => "Great-Grandparents",
                4 => "2nd Great-Grandparents", 5 => "3rd Great-Grandparents",
                6 => "4th Great-Grandparents"}
  def gen_label(n), do: Map.get(@gen_labels, n, "Generation #{n}")

  # Returns the slot path of position idx (0-based) in the given generation.
  # E.g. slot_at(2, 0)="SS", slot_at(2, 2)="DS"
  def slot_at(gen, idx) do
    Enum.map((gen - 1)..0//-1, fn bit ->
      if rem(div(idx, Integer.pow(2, bit)), 2) == 1, do: "D", else: "S"
    end)
    |> Enum.join()
  end
end
