defmodule RanchPhx.Animals.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    belongs_to :animal, RanchPhx.Animals.Animal

    field :title,       :string
    field :doc_type,    :string
    field :file_url,    :string
    field :file_size,   :integer
    field :mime_type,   :string
    field :description, :string
    field :doc_date,    :date

    timestamps()
  end

  @doc_types ~w(registration coggins health_cert dna_report bill_of_sale invoice brand_inspection contract other)

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:animal_id, :title, :doc_type, :file_url, :file_size, :mime_type, :description, :doc_date])
    |> validate_required([:animal_id, :file_url])
  end

  def doc_types, do: @doc_types

  def type_label("health_cert"),     do: "Health Certificate"
  def type_label("dna_report"),      do: "DNA Report"
  def type_label("bill_of_sale"),    do: "Bill of Sale"
  def type_label("brand_inspection"), do: "Brand Inspection"
  def type_label(t), do: t |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
end
