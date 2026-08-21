defmodule RanchPhx.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :animal_id,  references(:animals, on_delete: :delete_all), null: false
      add :title,      :string, null: false
      add :doc_type,   :string  # registration | coggins | health_cert | dna_report | bill_of_sale | invoice | other
      add :file_url,   :string, null: false
      add :file_size,  :integer
      add :mime_type,  :string
      add :description, :text
      add :doc_date,   :date

      timestamps()
    end

    create index(:documents, [:animal_id])
    create index(:documents, [:doc_type])
  end
end
