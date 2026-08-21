defmodule RanchPhx.Animals.DocType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "doc_types" do
    field :name,     :string
    field :position, :integer, default: 0
    timestamps()
  end

  def changeset(doc_type, attrs) do
    doc_type
    |> cast(attrs, [:name, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:name)
  end
end
