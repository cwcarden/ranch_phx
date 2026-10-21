defmodule RanchPhx.Training.Book do
  use Ecto.Schema
  import Ecto.Changeset

  # A horse's training book: one horse following one program.
  schema "training_books" do
    belongs_to :horse, RanchPhx.Training.Horse
    belongs_to :program, RanchPhx.Training.Program
    belongs_to :stage_override, RanchPhx.Training.Stage

    field :status, :string, default: "active"
    field :started_on, :date
    field :notes, :string

    has_many :sessions, RanchPhx.Training.Session
    has_many :goals, RanchPhx.Training.Goal, preload_order: [asc: :position, asc: :id]

    timestamps()
  end

  @statuses ~w(active paused finished)

  def changeset(book, attrs) do
    book
    |> cast(attrs, [:horse_id, :program_id, :status, :started_on, :notes])
    |> validate_required([:horse_id, :program_id, :started_on])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:horse_id,
      name: :training_books_one_active_per_horse,
      message: "already has an open training book"
    )
  end
end
