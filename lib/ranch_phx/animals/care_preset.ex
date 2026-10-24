defmodule RanchPhx.Animals.CarePreset do
  @moduledoc "A quick-add button on the Records tab (e.g. Core EQ Innovator, Deworming)."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(horse dog other)
  @units ~w(weeks months)

  schema "care_presets" do
    field :kind, :string
    field :label, :string
    field :record_type, :string
    field :title, :string
    field :product, :string
    field :interval_value, :integer
    field :interval_unit, :string
    field :position, :integer, default: 0

    timestamps()
  end

  def kinds, do: @kinds
  def units, do: @units

  @doc "Presets are shared by kind; cattle and anything else use \"other\"."
  def kind_for(kind) when kind in ["horse", "dog"], do: kind
  def kind_for(_), do: "other"

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, [
      :kind,
      :label,
      :record_type,
      :title,
      :product,
      :interval_value,
      :interval_unit,
      :position
    ])
    |> update_change(:label, &String.trim/1)
    |> update_change(:title, &String.trim/1)
    |> update_change(:product, &String.trim/1)
    |> validate_required([:kind, :label, :record_type, :title])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:label, max: 30)
    |> validate_number(:interval_value, greater_than: 0, less_than: 1000)
    |> validate_inclusion(:interval_unit, @units)
    |> clear_unit_without_value()
  end

  defp clear_unit_without_value(cs) do
    if get_field(cs, :interval_value), do: cs, else: put_change(cs, :interval_unit, nil)
  end

  @doc "The interval as `{:months, n}` / `{:weeks, n}`, or nil."
  def interval(%__MODULE__{interval_value: n, interval_unit: "months"}) when is_integer(n),
    do: {:months, n}

  def interval(%__MODULE__{interval_value: n, interval_unit: "weeks"}) when is_integer(n),
    do: {:weeks, n}

  def interval(_), do: nil
end
