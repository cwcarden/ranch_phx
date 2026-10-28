defmodule RanchPhx.Repo.Migrations.AllowLongeingSaddleStages do
  use Ecto.Migration

  # The 17–24 month stages call for longeing (free longeing in the round pen, then
  # longeing saddled), but their session types left it out, so logging it warned
  # "Longeing isn't part of this stage yet."
  @stages [
    "Saddle & pad",
    "Saddling & ground driving",
    "Getting ready to ride",
    "Backing & first rides"
  ]

  def up do
    execute fn ->
      repo().query!(
        """
        UPDATE training_stages
        SET session_types = array_append(session_types, 'longeing'), updated_at = now()
        WHERE name = ANY($1) AND NOT ('longeing' = ANY(session_types))
        """,
        [@stages]
      )
    end
  end

  def down, do: :ok
end
