defmodule RanchPhxWeb.CoverFocusTest do
  use RanchPhxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RanchPhx.Animals
  alias RanchPhx.Animals.Animal

  setup :register_and_log_in_user

  test "tapping the cover photo frames it the same on the card and the profile", %{conn: conn} do
    {:ok, a} =
      Animals.create_animal(%{name: "Asher", kind: "horse", cover_photo_url: "/uploads/asher.jpg"})

    {:ok, view, _} = live(conn, ~p"/animals/#{a.id}")
    render_click(view, "open_focus", %{})
    assert has_element?(view, "#focus-sheet")

    render_click(view, "set_cover_focus", %{"x" => "71.6", "y" => "18.2"})
    assert Animals.get_animal!(a.id).cover_position == "72% 18%"
    assert render(view) =~ "object-position: 72% 18%"

    {:ok, home, _} = live(conn, ~p"/")
    assert render(home) =~ "object-position: 72% 18%"
  end

  test "only real positions are used" do
    assert Animal.cover_focus(%{cover_position: "top"}) == "top"
    assert Animal.cover_focus(%{cover_position: "40% 20%"}) == "40% 20%"
    assert Animal.cover_focus(%{cover_position: "red; background: url(x)"}) == "center"
    assert Animal.cover_focus(%{cover_position: nil}) == "center"
  end
end
