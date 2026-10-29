defmodule RanchPhxWeb.SiriAuth do
  @moduledoc "The Siri Shortcuts' key check (Authorization: Bearer rk_…, a superuser's key)."
  import Plug.Conn
  alias RanchPhx.Accounts
  alias RanchPhx.Accounts.Scope

  def authorize(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %{} = user <- Accounts.get_user_by_api_token(String.trim(token)),
         true <- Scope.superuser?(Scope.for_user(user)) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end
end
