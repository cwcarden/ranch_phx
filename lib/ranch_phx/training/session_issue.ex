defmodule RanchPhx.Training.SessionIssue do
  use Ecto.Schema
  import Ecto.Changeset

  # How one session moved one issue: better, same or worse.
  schema "training_session_issues" do
    belongs_to :session, RanchPhx.Training.Session
    belongs_to :issue, RanchPhx.Training.Issue

    field :progress, :string
    field :note, :string
  end

  @progress [{"better", "Better"}, {"same", "Same"}, {"worse", "Worse"}]
  def progress_options, do: @progress

  def changeset(mark, attrs) do
    mark
    |> cast(attrs, [:issue_id, :progress, :note])
    |> validate_required([:issue_id, :progress])
    |> validate_inclusion(:progress, Enum.map(@progress, &elem(&1, 0)))
  end
end
