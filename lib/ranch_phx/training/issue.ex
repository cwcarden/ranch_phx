defmodule RanchPhx.Training.Issue do
  use Ecto.Schema
  import Ecto.Changeset

  # Something you're working through with a horse ("Picking up left hind").
  schema "training_issues" do
    belongs_to :horse, RanchPhx.Training.Horse
    belongs_to :activity, RanchPhx.Training.Activity

    field :title, :string
    field :side, :string
    field :status, :string, default: "open"
    field :notes, :string
    field :opened_on, :date
    field :solved_on, :date

    has_many :marks, RanchPhx.Training.SessionIssue

    timestamps()
  end

  @statuses [{"open", "Open"}, {"improving", "Improving"}, {"solved", "Solved"}]
  def statuses, do: @statuses

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, [
      :horse_id,
      :activity_id,
      :title,
      :side,
      :status,
      :notes,
      :opened_on,
      :solved_on
    ])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:horse_id, :title, :opened_on])
    |> validate_length(:title, max: 200)
    |> validate_inclusion(:status, Enum.map(@statuses, &elem(&1, 0)))
    |> validate_inclusion(:side, ~w(left right both))
  end
end
