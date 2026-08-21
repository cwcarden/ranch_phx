defmodule RanchPhx.Repo.Migrations.AddCoverPositionToAnimals do
  use Ecto.Migration

  def change do
    alter table(:animals) do
      add :cover_position, :string, default: "center"
    end
  end
end
