defmodule RanchPhx.Training.Activity do
  use Ecto.Schema
  import Ecto.Changeset

  # Something you work on in a session (groundwork, feet, longeing…). Editable list.
  schema "training_activities" do
    field :slug, :string
    field :name, :string
    field :position, :integer, default: 0
    field :archived, :boolean, default: false

    timestamps()
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:slug, :name, :position, :archived])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:slug, :name])
    |> validate_length(:name, max: 40)
    |> unique_constraint(:slug)
  end
end
