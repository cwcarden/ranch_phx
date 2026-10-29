defmodule RanchPhxWeb.PageControllerTest do
  use RanchPhxWeb.ConnCase

  test "GET / sends visitors who aren't signed in to the sign-in page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
