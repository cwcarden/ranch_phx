defmodule RanchPhx.Training.Program do
  use Ecto.Schema

  schema "training_programs" do
    field :slug, :string
    field :name, :string
    field :description, :string

    has_many :stages, RanchPhx.Training.Stage, preload_order: [asc: :position]

    timestamps()
  end
end
