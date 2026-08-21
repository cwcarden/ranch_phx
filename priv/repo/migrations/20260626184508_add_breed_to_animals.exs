defmodule RanchPhx.Repo.Migrations.AddBreedToAnimals do
  use Ecto.Migration

  def change do
    alter table(:animals) do
      add :breed, :string
    end
  end
end
