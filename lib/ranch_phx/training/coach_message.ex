defmodule RanchPhx.Training.CoachMessage do
  use Ecto.Schema

  schema "training_coach_messages" do
    belongs_to :book, RanchPhx.Training.Book
    # The first message of the conversation; nil on that first message itself.
    belongs_to :thread, __MODULE__

    field :question, :string
    field :answer, :string
    # Short labels for what the Coach looked up ("sessions Oct 1–21").
    field :checked, {:array, :string}, default: []
    field :model, :string

    timestamps(updated_at: false)
  end
end
