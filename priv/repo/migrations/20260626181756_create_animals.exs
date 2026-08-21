defmodule RanchPhx.Repo.Migrations.CreateAnimals do
  use Ecto.Migration

  def change do
    create table(:animals) do
      add :name,                :string,  null: false
      add :kind,                :string,  null: false  # horse | cattle | dog
      add :sex,                 :string
      add :status,              :string,  default: "active"
      add :owned,               :boolean, default: true

      add :registration_number, :string
      add :tattoo,              :string
      add :freeze_brand,        :string
      add :microchip,           :string
      add :dna_id,              :string

      add :color,               :string
      add :markings,            :text
      add :height_hh,           :decimal, precision: 4, scale: 1
      add :weight_lbs,          :integer

      add :birth_date,          :date
      add :death_date,          :date

      add :breeder,             :string
      add :owner,               :string
      add :location,            :string

      add :sire_id,             references(:animals, on_delete: :nilify_all)
      add :dam_id,              references(:animals, on_delete: :nilify_all)

      add :cover_photo_url,     :string
      add :is_favorite,         :boolean, default: false
      add :notes,               :text

      timestamps()
    end

    create index(:animals, [:kind])
    create index(:animals, [:status])
    create index(:animals, [:owned])
    create index(:animals, [:sire_id])
    create index(:animals, [:dam_id])
    create index(:animals, [:name])
  end
end
