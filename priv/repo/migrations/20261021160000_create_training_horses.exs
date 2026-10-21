defmodule RanchPhx.Repo.Migrations.CreateTrainingHorses do
  use Ecto.Migration

  # Training gets its own horse profiles: a horse can be linked to a ranch
  # animal, or be any outside horse (a client's horse, one you're riding for someone).
  def up do
    create table(:training_horses) do
      add :animal_id, references(:animals, on_delete: :nilify_all)
      add :name,      :string, null: false
      add :foaled_on, :date
      add :sex,       :string
      add :breed,     :string
      add :color,     :string
      add :owner,     :string
      add :photo_url, :string
      add :notes,     :text

      timestamps()
    end

    create unique_index(:training_horses, [:animal_id], where: "animal_id IS NOT NULL")

    alter table(:training_books) do
      add :horse_id, references(:training_horses, on_delete: :delete_all)
    end

    flush()

    # Existing books were tied to ranch animals: give each of those a linked profile.
    execute """
    INSERT INTO training_horses (animal_id, name, foaled_on, sex, breed, color, owner, photo_url, inserted_at, updated_at)
    SELECT DISTINCT a.id, a.name, a.birth_date, a.sex, a.breed, a.color, a.owner, a.cover_photo_url, NOW(), NOW()
    FROM animals a JOIN training_books b ON b.animal_id = a.id
    """

    execute """
    UPDATE training_books b SET horse_id = h.id
    FROM training_horses h WHERE h.animal_id = b.animal_id
    """

    drop index(:training_books, [:animal_id], name: :training_books_one_active_per_animal)
    drop index(:training_books, [:animal_id])

    alter table(:training_books) do
      modify :horse_id, :bigint, null: false
      remove :animal_id
    end

    create index(:training_books, [:horse_id])

    create unique_index(:training_books, [:horse_id],
             where: "status = 'active'",
             name: :training_books_one_active_per_horse)
  end

  def down do
    alter table(:training_books) do
      add :animal_id, references(:animals, on_delete: :delete_all)
    end

    flush()

    execute """
    UPDATE training_books b SET animal_id = h.animal_id
    FROM training_horses h WHERE h.id = b.horse_id
    """

    # Books for outside horses have no ranch animal to go back to.
    execute "DELETE FROM training_books WHERE animal_id IS NULL"

    drop index(:training_books, [:horse_id], name: :training_books_one_active_per_horse)
    drop index(:training_books, [:horse_id])

    alter table(:training_books) do
      remove :horse_id
      modify :animal_id, :bigint, null: false
    end

    create index(:training_books, [:animal_id])

    create unique_index(:training_books, [:animal_id],
             where: "status = 'active'",
             name: :training_books_one_active_per_animal)

    drop table(:training_horses)
  end
end
