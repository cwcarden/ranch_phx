defmodule RanchPhxWeb.AnimalSidebarTest do
  use RanchPhxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RanchPhx.Animals

  setup :register_and_log_in_user

  test "the animal page lists the other animals, with what needs attention",
       %{conn: conn} do
    {:ok, asher} = Animals.create_animal(%{name: "Asher", kind: "horse"})
    {:ok, ruby} = Animals.create_animal(%{name: "Ruby", kind: "dog"})

    {:ok, _} =
      Animals.create_record(%{
        "animal_id" => ruby.id,
        "record_type" => "vaccination",
        "title" => "Rabies vaccine",
        "date" => Date.add(RanchPhx.LocalTime.today(), -370),
        "next_due_date" => Date.add(RanchPhx.LocalTime.today(), -5)
      })

    {:ok, view, _} = live(conn, ~p"/animals/#{asher.id}?tab=records")
    assert has_element?(view, "#side-#{asher.id}.on")
    assert has_element?(view, "#side-#{ruby.id}", "Rabies vaccine overdue")
    # Opens the other animal on the same tab.
    assert has_element?(view, ~s|#side-#{ruby.id}[href="/animals/#{ruby.id}?tab=records"]|)
  end

  test "no sidebar with only one animal", %{conn: conn} do
    {:ok, asher} = Animals.create_animal(%{name: "Asher", kind: "horse"})
    {:ok, view, _} = live(conn, ~p"/animals/#{asher.id}")
    refute has_element?(view, ".as-side")
  end
end
