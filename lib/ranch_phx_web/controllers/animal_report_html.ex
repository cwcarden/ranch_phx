defmodule RanchPhxWeb.AnimalReportHTML do
  use RanchPhxWeb, :html
  alias RanchPhx.Animals.{Animal, CareSchedule}
  embed_templates "animal_report_html/*"
end
