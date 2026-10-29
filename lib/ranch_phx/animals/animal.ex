defmodule RanchPhx.Animals.Animal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "animals" do
    field :name,                :string
    # What he's called around the barn ("Asher" for Gimels Soldier Cat): shown first, and what Siri listens for.
    field :barn_name,           :string
    field :kind,                :string   # horse | cattle | dog
    field :sex,                 :string
    field :status,              :string, default: "active"
    field :owned,               :boolean, default: true

    field :registration_number, :string
    field :tattoo,              :string
    field :freeze_brand,        :string
    field :microchip,           :string
    field :dna_id,              :string

    field :breed,               :string
    field :color,               :string
    field :markings,            :string
    field :height_hh,           :decimal
    field :weight_lbs,          :integer

    field :birth_date,          :date
    field :death_date,          :date

    field :breeder,             :string
    field :owner,               :string
    field :location,            :string

    belongs_to :sire, __MODULE__
    belongs_to :dam,  __MODULE__

    has_many :sired_offspring, __MODULE__, foreign_key: :sire_id
    has_many :damed_offspring, __MODULE__, foreign_key: :dam_id

    has_many :timeline_events, RanchPhx.Animals.TimelineEvent
    has_many :records,         RanchPhx.Animals.Record
    has_many :genetics,        RanchPhx.Animals.Genetics
    has_many :documents,       RanchPhx.Animals.Document
    has_many :photos,          RanchPhx.Animals.Photo

    field :cover_photo_url,    :string
    field :cover_position,     :string, default: "center"
    field :is_favorite,        :boolean, default: false
    field :notes,              :string

    timestamps()
  end

  @kinds   ~w(horse cattle dog)
  @statuses ~w(active retired sold deceased)
  @required ~w(name kind)a

  @doc "The name to show first: the barn name when there is one, else the registered name."
  def display_name(%{barn_name: b} = a) when is_binary(b) and b != "", do: String.trim(b) |> then(&if(&1 == "", do: a.name, else: &1))
  def display_name(%{name: name}), do: name

  @doc "The registered name, when it's shown under a different barn name; else nil."
  def registered_name(%{barn_name: b, name: name}) when is_binary(b) and b != "" do
    if String.trim(b) in ["", name], do: nil, else: name
  end

  def registered_name(_), do: nil

  def changeset(animal, attrs) do
    animal
    |> cast(attrs, [
      :name, :barn_name, :kind, :sex, :status, :owned,
      :registration_number, :tattoo, :freeze_brand, :microchip, :dna_id,
      :breed, :color, :markings, :height_hh, :weight_lbs,
      :birth_date, :death_date,
      :breeder, :owner, :location,
      :sire_id, :dam_id,
      :cover_photo_url, :cover_position, :is_favorite, :notes
    ])
    |> validate_required(@required)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_no_self_parent()
  end

  defp validate_no_self_parent(changeset) do
    id = get_field(changeset, :id)
    sire_id = get_field(changeset, :sire_id)
    dam_id  = get_field(changeset, :dam_id)

    changeset
    |> then(fn cs -> if id && sire_id == id, do: add_error(cs, :sire_id, "cannot be the animal itself"), else: cs end)
    |> then(fn cs -> if id && dam_id  == id, do: add_error(cs, :dam_id,  "cannot be the animal itself"), else: cs end)
  end

  def age_label(%__MODULE__{birth_date: nil}), do: nil
  def age_label(%__MODULE__{birth_date: dob}) do
    today = RanchPhx.LocalTime.today()
    years = today.year - dob.year - (if {today.month, today.day} < {dob.month, dob.day}, do: 1, else: 0)
    cond do
      years >= 2 -> "#{years} yrs"
      years == 1 -> "1 yr"
      true ->
        months = (today.year * 12 + today.month) - (dob.year * 12 + dob.month)
        "#{max(months, 0)} mo"
    end
  end

  def status_color("active"),   do: "green"
  def status_color("retired"),  do: "amber"
  def status_color("sold"),     do: "blue"
  def status_color("deceased"), do: "gray"
  def status_color(_),          do: "gray"
end
