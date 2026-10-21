defmodule RanchPhx.Training.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "training_sessions" do
    belongs_to :book, RanchPhx.Training.Book

    # Generated when the log form opens, so a re-sent form updates the same row.
    # Editing a session reuses its client_id.
    field :client_id, Ecto.UUID
    field :date, :date
    field :minutes, :integer
    field :tags, {:array, :string}, default: []
    field :note, :string
    field :source, :string, default: "typed"

    has_many :activities, RanchPhx.Training.SessionActivity, preload_order: [asc: :position]

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:book_id, :client_id, :date, :minutes, :tags, :note, :source])
    |> update_change(:tags, fn tags -> tags |> Enum.reject(&(&1 == "")) |> Enum.uniq() end)
    |> validate_required([:book_id, :client_id, :date])
    |> validate_number(:minutes, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_inclusion(:source, ~w(typed voice))
  end
end
