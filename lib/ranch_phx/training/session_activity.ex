defmodule RanchPhx.Training.SessionActivity do
  use Ecto.Schema
  import Ecto.Changeset

  # One activity within a session, with how it went and which side.
  schema "training_session_activities" do
    belongs_to :session, RanchPhx.Training.Session
    belongs_to :activity, RanchPhx.Training.Activity

    field :position, :integer, default: 0
    field :result, :string
    field :side, :string
    field :note, :string
  end

  @results [{"good", "Good"}, {"mixed", "Mixed"}, {"trouble", "Trouble"}]
  @sides [{"left", "Left"}, {"right", "Right"}, {"both", "Both"}]

  def results, do: @results
  def sides, do: @sides

  def changeset(sa, attrs) do
    sa
    |> cast(attrs, [:activity_id, :position, :result, :side, :note])
    |> validate_required([:activity_id])
    |> validate_inclusion(:result, Enum.map(@results, &elem(&1, 0)))
    |> validate_inclusion(:side, Enum.map(@sides, &elem(&1, 0)))
  end
end
