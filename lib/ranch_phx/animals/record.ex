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

  # Categories live in the record_categories DB table (customizable, same as
  # types) — kept shaped as %{id, label, color} here so existing call sites
  # (category filter bar, add-record form) don't need to change. `db_id` and
  # `is_builtin` are extra, for the inline category manager.
  def categories do
    RanchPhx.Repo.all(
      from rc in RanchPhx.Animals.RecordCategory,
      order_by: [asc: rc.position, asc: rc.label]
    )
    |> Enum.map(&%{id: &1.slug, label: &1.label, color: &1.color, db_id: &1.id, is_builtin: &1.is_builtin})
  end

  def category_color(cat_id) do
    case RanchPhx.Repo.one(
      from rc in RanchPhx.Animals.RecordCategory,
      where: rc.slug == ^cat_id,
      select: rc.color,
      limit: 1
    ) do
      nil   -> "#6b7280"
      color -> color
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
