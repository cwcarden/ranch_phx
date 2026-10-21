defmodule RanchPhx.Training.Stage do
  use Ecto.Schema

  schema "training_stages" do
    belongs_to :program, RanchPhx.Training.Program

    field :position, :integer
    field :name, :string
    field :from_age_months, :integer
    field :summary, :string
    field :focus, {:array, :string}, default: []
    field :guardrail, :string
    field :max_session_minutes, :integer
    field :max_sessions_per_week, :integer
    field :session_types, {:array, :string}, default: []

    timestamps()
  end
end
