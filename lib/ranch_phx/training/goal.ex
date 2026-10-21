defmodule RanchPhx.Training.Goal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "training_goals" do
    belongs_to :book, RanchPhx.Training.Book

    field :title, :string
    field :target_date, :date
    field :status, :string, default: "active"
    field :notes, :string
    field :position, :integer, default: 0
    field :done_on, :date

    timestamps()
  end

  @statuses ~w(active done dropped)
  def statuses, do: @statuses

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:book_id, :title, :target_date, :status, :notes, :position, :done_on])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:book_id, :title])
    |> validate_length(:title, max: 200)
    |> validate_inclusion(:status, @statuses)
  end
end
