defmodule RanchPhx.Repo.Migrations.AddBarnNameToAnimals do
  use Ecto.Migration

  def change do
    alter table(:animals) do
      add :barn_name, :string
    end
  end
end
