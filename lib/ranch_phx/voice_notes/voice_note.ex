defmodule RanchPhx.VoiceNotes.VoiceNote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "voice_notes" do
    field :text, :string
    # pending → done (saved as records) or dismissed
    field :status, :string, default: "pending"
    belongs_to :animal, RanchPhx.Animals.Animal
    belongs_to :user, RanchPhx.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:text, :status, :animal_id, :user_id])
    |> update_change(:text, &(&1 |> String.trim() |> String.slice(0, 2000)))
    |> validate_required([:text])
    |> validate_inclusion(:status, ~w(pending done dismissed))
  end
end
