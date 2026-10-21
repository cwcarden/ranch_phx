defmodule RanchPhx.Training.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  # How the horse was: good, a problem, or a health flag. Editable list.
  schema "training_tags" do
    field :slug, :string
    field :name, :string
    field :kind, :string, default: "problem"
    field :position, :integer, default: 0
    field :archived, :boolean, default: false

    timestamps()
  end

  @kinds ~w(good problem health)
  def kinds, do: @kinds

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:slug, :name, :kind, :position, :archived])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:slug, :name, :kind])
    |> validate_length(:name, max: 40)
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:slug)
  end
end
