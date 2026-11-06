defmodule RanchPhxWeb.DocumentsMenuTest do
  use RanchPhxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RanchPhx.Animals

  setup :register_and_log_in_user

  setup do
    {:ok, cat} =
      Animals.create_animal(%{name: "Gimels Soldier Cat", barn_name: "Asher", kind: "horse"})

    for i <- 1..23 do
      {:ok, _} =
        Animals.create_document(%{
          animal_id: cat.id,
          title: if(i == 7, do: "Health certificate 2026", else: "Paper #{i}"),
          doc_type: if(rem(i, 2) == 0, do: "Coggins", else: "Other"),
          doc_date: Date.add(~D[2026-01-01], i),
          file_url: "/uploads/animals/#{cat.id}/documents/p#{i}.pdf"
        })
    end

    %{cat: cat}
  end

  test "documents don't grow the page: 10 at a time, search finds the rest, the form is a pop-up",
       %{conn: conn, cat: cat} do
    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}?tab=documents")

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#doc-list .dk-row")
           |> Enum.count() == 10

    assert has_element?(view, "#doc-more", "13 left")
    refute has_element?(view, "#doc-upload-form")

    view |> element("#doc-more") |> render_click()

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#doc-list .dk-row")
           |> Enum.count() == 20

    view |> element("#doc-search") |> render_keyup(%{"value" => "health"})

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#doc-list .dk-row")
           |> Enum.count() == 1

    refute has_element?(view, "#doc-more")

    view |> element("#doc-add") |> render_click()
    assert has_element?(view, "#doc-sheet #doc-upload-form")
    assert has_element?(view, "#doc-sheet #doc-types")
    render_click(view, "close_doc_form", %{})
    refute has_element?(view, "#doc-sheet")
  end

  test "each document has a labeled delete", %{conn: conn, cat: cat} do
    [doc | _] = Animals.get_animal_with_pedigree!(cat.id).documents
    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}?tab=documents")
    assert has_element?(view, "#delete-doc-#{doc.id}[aria-label='Delete #{doc.title}']")
    view |> element("#delete-doc-#{doc.id}") |> render_click()
    refute has_element?(view, "#doc-#{doc.id}")
  end

  test "the ⋯ menu has every tab and page, and every page has the full menu", %{
    conn: conn,
    cat: cat
  } do
    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}")

    for tab <- ~w(overview records documents photos pedigree timeline genetics expenses),
        do: assert(has_element?(view, "#actions-sheet #act-tab-#{tab}"))

    for href <- [
          "/training",
          "/conformation",
          "/notifications",
          "/barn.html",
          "/animals/#{cat.id}/feed",
          "/animals/#{cat.id}/hooves"
        ],
        do: assert(has_element?(view, "#actions-sheet a[href='#{href}']"))

    view |> element("#act-tab-documents") |> render_click()
    assert has_element?(view, "#doc-list")

    # Any other page: ☰ in the top bar opens the same list.
    {:ok, hooves, _} = live(conn, ~p"/animals/#{cat.id}/hooves")
    assert has_element?(hooves, "#site-menu a[href='/training']")
    assert has_element?(hooves, ".tr-menu")
  end
end
