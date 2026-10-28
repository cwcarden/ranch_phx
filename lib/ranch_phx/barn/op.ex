defmodule RanchPhx.Barn.Op do
  @moduledoc "An addition made offline in Barn mode, recorded once it's applied."
  use Ecto.Schema

  schema "barn_ops" do
    field :client_id, :string
    field :kind, :string
    field :result, :map, default: %{}
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
