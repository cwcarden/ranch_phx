defmodule RanchPhx.Animals.RecordCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "record_categories" do
    field :slug,       :string
    field :label,      :string
    field :color,      :string
    field :position,   :integer, default: 0
    field :is_builtin, :boolean, default: false

    timestamps()
  end

  def changeset(rc, attrs) do
    rc
    |> cast(attrs, [:slug, :label, :color, :position])
    |> validate_required([:slug, :label, :color])
    |> validate_format(:slug, ~r/^[a-z0-9_]+$/, message: "only lowercase letters, numbers, underscores")
    |> validate_length(:label, min: 1, max: 60)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a hex color like #6366f1")
    |> unique_constraint(:slug)
  end
end
