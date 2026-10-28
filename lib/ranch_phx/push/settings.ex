defmodule RanchPhx.Push.Settings do
  @moduledoc "One person's notification choices (defaults: 7 a.m. and 6 p.m., everything on)."
  use Ecto.Schema
  import Ecto.Changeset

  schema "push_settings" do
    belongs_to :user, RanchPhx.Accounts.User
    field :morning_on, :boolean, default: true
    field :morning_hour, :integer, default: 7
    field :evening_on, :boolean, default: true
    field :evening_hour, :integer, default: 18
    field :doses, :boolean, default: true
    field :care, :boolean, default: true
    field :care_days_ahead, :integer, default: 1
    field :overdue, :boolean, default: true
    field :muted_animal_ids, {:array, :integer}, default: []
    timestamps(type: :utc_datetime)
  end

  @fields ~w(morning_on morning_hour evening_on evening_hour doses care care_days_ahead overdue muted_animal_ids)a

  def changeset(s, attrs) do
    s
    |> cast(attrs, @fields)
    |> validate_inclusion(:morning_hour, 4..12)
    |> validate_inclusion(:evening_hour, 14..22)
    |> validate_inclusion(:care_days_ahead, [0, 1, 3, 7, 14])
  end
end
