defmodule RanchPhx.Repo.Migrations.CreateGenetics do
  use Ecto.Migration

  def change do
    create table(:genetics) do
      add :animal_id,  references(:animals, on_delete: :delete_all), null: false
      add :panel_name, :string  # "AQHA 5-panel" | "color" | "custom"
      add :lab,        :string
      add :test_date,  :date
      add :report_url, :string
      add :results,    :map, default: %{}
      # results shape: %{"HERDA" => %{"result" => "N/N", "status" => "clear"},
      #                   "HYPP"  => %{"result" => "N/N", "status" => "clear"}, ...}
      add :notes,      :text

      timestamps()
    end

    create index(:genetics, [:animal_id])
  end
end
