defmodule RanchPhx.Animals.Genetics do
  use Ecto.Schema
  import Ecto.Changeset

  schema "genetics" do
    belongs_to :animal, RanchPhx.Animals.Animal

    field :panel_name, :string
    field :lab,        :string
    field :test_date,  :date
    field :report_url, :string
    field :results,    :map, default: %{}
    field :notes,      :string

    timestamps()
  end

  # Standard AQHA 5-panel tests
  @aqha_panel ~w(HERDA HYPP GBED MH PSSM1)
  # Color genetics
  @color_panel ~w(Extension Agouti Cream Dun Grey Roan Tobiano Frame Sabino)

  def changeset(genetics, attrs) do
    genetics
    |> cast(attrs, [:animal_id, :panel_name, :lab, :test_date, :report_url, :results, :notes])
    |> validate_required([:animal_id, :panel_name])
  end

  def aqha_panel, do: @aqha_panel
  def color_panel, do: @color_panel

  def result_status_color("N/N"),      do: "green"   # clear
  def result_status_color("N/H"),      do: "amber"   # carrier
  def result_status_color("H/H"),      do: "red"     # affected
  def result_status_color("Positive"), do: "green"
  def result_status_color("Negative"), do: "red"
  def result_status_color(_),          do: "gray"

  def result_label("N/N"), do: "Clear"
  def result_label("N/H"), do: "Carrier"
  def result_label("H/H"), do: "Affected"
  def result_label(r),     do: r
end
