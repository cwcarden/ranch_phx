defmodule RanchPhxWeb.FeedPlanTest do
  use RanchPhxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias RanchPhx.{Animals, FeedPlans, LocalTime}

  setup :register_and_log_in_user

  setup do
    {:ok, cat} =
      Animals.create_animal(%{name: "Gimels Soldier Cat", barn_name: "Asher", kind: "horse"})

    %{cat: cat}
  end

  defp fill(view, sections) do
    params =
      sections
      |> Enum.with_index()
      |> Map.new(fn {{t, b}, i} -> {"#{i}", %{"title" => t, "body" => b}} end)

    view |> form("#feed-form", %{"sections" => params}) |> render_submit()
  end

  test "write the plan on the phone, print it, and share a link you can turn off",
       %{conn: conn, cat: cat} do
    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}/feed")
    assert has_element?(view, "#sec-0 input[value='Morning feed']")
    refute has_element?(view, "#share-url")

    fill(view, [
      {"Morning feed",
       "2 dry pounds of Purina Enrich Plus\nWhere to find it: White feed bin in the tack room"},
      {"Hay", "Keep the hay saver bin full"},
      {"Bedding", ""},
      {"Emergency contacts", "Vet: 806-622-0803"}
    ])

    [plan] = RanchPhx.Repo.all(RanchPhx.FeedPlans.FeedPlan)
    assert Enum.any?(plan.sections, &(&1["title"] == "Hay" and &1["body"] =~ "hay saver"))

    # The printable page: empty sections left out, labels in bold, phones tappable.
    html = conn |> get(~p"/animals/#{cat.id}/feed/print") |> html_response(200)
    assert html =~ "Feeding Schedule"
    assert html =~ "Asher"
    assert html =~ "<b>Where to find it:</b>"
    assert html =~ ~s(href="tel:8066220803")
    refute html =~ "Bedding"
    assert html =~ "Save / Share PDF"

    # Sharing is off until turned on; the link doesn't open.
    public = build_conn()
    assert public |> get(~p"/share/feed/#{plan.share_token}") |> response(404) =~ "isn't shared"

    view |> element("#share-toggle") |> render_click()
    assert has_element?(view, "#share-url", "/share/feed/#{plan.share_token}")
    assert has_element?(view, "#send-link")

    html = build_conn() |> get(~p"/share/feed/#{plan.share_token}") |> html_response(200)
    assert html =~ "2 dry pounds of Purina Enrich Plus"
    assert html =~ "always shows the latest plan"
    refute html =~ "‹ Back"

    # A change shows up on the same link.
    fill(view, [{"Morning feed", "3 dry pounds of Purina Enrich Plus"}])

    assert build_conn() |> get(~p"/share/feed/#{plan.share_token}") |> html_response(200) =~
             "3 dry pounds"

    # A new link retires the old one.
    view |> element("#new-link") |> render_click()
    new = FeedPlans.get_for_animal(cat.id)
    assert new.share_token != plan.share_token
    assert build_conn() |> get(~p"/share/feed/#{plan.share_token}") |> response(404)
    assert build_conn() |> get(~p"/share/feed/#{new.share_token}") |> response(200)

    # Turned off: nobody can open it.
    view |> element("#share-toggle") |> render_click()
    refute has_element?(view, "#share-url")
    assert build_conn() |> get(~p"/share/feed/#{new.share_token}") |> response(404)
  end

  test "running treatments are added to the plan by themselves", %{conn: conn, cat: cat} do
    today = LocalTime.today()

    {:ok, _} =
      Animals.create_record(%{
        "animal_id" => cat.id,
        "record_type" => "medication",
        "title" => "Bute",
        "description" => "1 gram in feed · daily for 5 days",
        "date" => Date.add(today, -1),
        "course_done" => [Date.add(today, -1)]
      })

    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}/feed")
    assert has_element?(view, "#feed-care", "Bute")
    assert has_element?(view, "#feed-care", "day 2 of 5 today")

    fill(view, [{"Morning feed", "2 lb ration balancer"}])
    plan = FeedPlans.get_for_animal(cat.id)
    view |> element("#share-toggle") |> render_click()

    html = build_conn() |> get(~p"/share/feed/#{plan.share_token}") |> html_response(200)
    assert html =~ "Medicine and daily care right now"
    assert html =~ "<b>Bute:</b>"
    assert html =~ "1 gram in feed"
  end

  test "the animal page links to it", %{conn: conn, cat: cat} do
    {:ok, view, _} = live(conn, ~p"/animals/#{cat.id}?tab=records")
    assert has_element?(view, "#feed-plan-link[href='/animals/#{cat.id}/feed']")
    assert has_element?(view, "#act-feed")
  end

  test "a made-up link shows nothing" do
    assert build_conn() |> get(~p"/share/feed/not-a-real-link-at-all-xx") |> response(404)
  end

  test "an open shared page can tell when the plan changed or was turned off", %{cat: cat} do
    {:ok, plan} =
      FeedPlans.save(FeedPlans.get_or_new(cat.id), [%{"title" => "Hay", "body" => "Keep it full"}])

    {:ok, plan} = FeedPlans.set_sharing(plan, true)
    path = ~p"/share/feed/#{plan.share_token}"

    html = build_conn() |> get(path) |> html_response(200)
    [_, v1] = Regex.run(~r/data-version="(\d+)"/, html)

    assert build_conn() |> get(path <> "/version") |> json_response(200) == %{
             "shared" => true,
             "v" => v1
           }

    # The page's PDF maker comes from under /share/, the only part open to the public.
    assert html =~ ~s(data-pdf-lib="/share/vendor/html2pdf.bundle.min.js")
    assert build_conn() |> get("/share/vendor/html2pdf.bundle.min.js") |> response(200)

    {:ok, plan} =
      FeedPlans.save(plan, [%{"title" => "Hay", "body" => "Out of hay: call Charles"}])

    %{"v" => v2} = build_conn() |> get(path <> "/version") |> json_response(200)
    assert v2 != v1

    {:ok, _} = FeedPlans.set_sharing(plan, false)
    assert build_conn() |> get(path <> "/version") |> json_response(404) == %{"shared" => false}
  end
end
