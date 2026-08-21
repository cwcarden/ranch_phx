defmodule RanchPhxWeb.PageController do
  use RanchPhxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
