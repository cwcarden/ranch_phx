defmodule RanchPhx.Training.SessionPhoto do
  use Ecto.Schema

  schema "training_session_photos" do
    belongs_to :session, RanchPhx.Training.Session

    field :url, :string
    field :position, :integer, default: 0

    timestamps(updated_at: false)
  end
end
