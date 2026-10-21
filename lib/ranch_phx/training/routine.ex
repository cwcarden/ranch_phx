defmodule RanchPhx.Training.Routine do
  use Ecto.Schema
  import Ecto.Changeset

  # A saved combo for one horse ("Usual groundwork") that fills the log form in one tap.
  schema "training_routines" do
    belongs_to :horse, RanchPhx.Training.Horse

    field :name, :string
    field :activity_ids, {:array, :integer}, default: []
    field :minutes, :integer
    field :tags, {:array, :string}, default: []

    timestamps()
  end

  def changeset(routine, attrs) do
    routine
    |> cast(attrs, [:horse_id, :name, :activity_ids, :minutes, :tags])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:horse_id, :name])
    |> validate_length(:name, max: 40)
    |> require_activities()
  end

  defp require_activities(changeset) do
    case get_field(changeset, :activity_ids) do
      [_ | _] -> changeset
      _ -> add_error(changeset, :activity_ids, "pick at least one activity first")
    end
  end
end
