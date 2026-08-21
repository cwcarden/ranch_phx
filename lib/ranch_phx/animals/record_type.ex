defmodule RanchPhx.Animals.RecordType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "record_types" do
    field :category,   :string
    field :slug,       :string
    field :label,      :string
    field :position,   :integer, default: 0
    field :is_builtin, :boolean, default: false

    timestamps()
  end

  def changeset(rt, attrs) do
    rt
    |> cast(attrs, [:category, :slug, :label, :position])
    |> validate_required([:category, :slug, :label])
    |> validate_format(:slug, ~r/^[a-z0-9_]+$/, message: "only lowercase letters, numbers, underscores")
    |> validate_length(:label, min: 1, max: 60)
    |> unique_constraint(:slug)
  end
end
