defmodule RanchPhx.Animals.Record do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "records" do
    belongs_to :animal, RanchPhx.Animals.Animal

    field :category,      :string
    field :record_type,   :string
    field :title,         :string
    field :description,   :string
    field :date,          :date
    field :next_due_date, :date
    field :location,      :string
    field :person,        :string
    field :cost,          :decimal
    field :tags,          {:array, :string}, default: []
    field :created_by,    :string
    field :notes,         :string

    timestamps()
  end

  # Static category metadata only — types live in the record_types DB table.
  @categories [
    %{id: "identification", label: "Identification", color: "#6366f1"},
    %{id: "health",         label: "Health",         color: "#2563eb"},
    %{id: "hoof_care",      label: "Hoof Care",      color: "#d97706"},
    %{id: "training",       label: "Training",       color: "#7c3aed"},
    %{id: "performance",    label: "Performance",    color: "#0891b2"},
    %{id: "nutrition",      label: "Nutrition",      color: "#16a34a"},
    %{id: "breeding",       label: "Breeding",       color: "#ec4899"},
    %{id: "transportation", label: "Transportation", color: "#64748b"},
    %{id: "media",          label: "Media",          color: "#0ea5e9"},
    %{id: "journal",        label: "Journal",        color: "#78716c"}
  ]

  def categories, do: @categories

  def category_color(cat_id) do
    case Enum.find(@categories, &(&1.id == cat_id)) do
      nil -> "#6b7280"
      cat -> cat.color
    end
  end

  def type_label(type_slug) do
    case RanchPhx.Repo.one(
      from rt in RanchPhx.Animals.RecordType,
      where: rt.slug == ^type_slug,
      select: rt.label,
      limit: 1
    ) do
      nil   -> type_slug |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
      label -> label
    end
  end

  @required ~w(animal_id record_type title date)a

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :animal_id, :category, :record_type, :title, :description, :date,
      :next_due_date, :location, :person, :cost,
      :tags, :created_by, :notes
    ])
    |> validate_required(@required)
    |> put_category()
  end

  defp put_category(changeset) do
    case get_field(changeset, :record_type) do
      nil -> changeset
      slug ->
        cat_slug = RanchPhx.Repo.one(
          from rt in RanchPhx.Animals.RecordType,
          where: rt.slug == ^slug,
          select: rt.category,
          limit: 1
        )
        put_change(changeset, :category, cat_slug)
    end
  end
end
