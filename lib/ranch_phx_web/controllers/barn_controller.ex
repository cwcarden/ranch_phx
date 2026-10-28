defmodule RanchPhxWeb.BarnController do
  @moduledoc """
  What Barn mode (/barn.html) talks to, signed in with the app's usual session:

    * `GET  /api/barn/snapshot`: everything to keep on the device, plus the photo list.
    * `POST /api/barn/sync`: `{"ops": [...]}`, additions made offline; answers per op.
    * `POST /api/barn/photo`: one photo taken offline (multipart), with its place.

  Writes need the same permission as editing in the app. Requests must come from the
  app's own pages (same origin), since this skips the form token the pages use.
  """
  use RanchPhxWeb, :controller
  alias RanchPhx.Barn
  alias RanchPhx.Accounts.Scope

  def snapshot(conn, _params) do
    snap = Barn.snapshot()

    json(conn, %{
      ok: true,
      can_edit: Scope.superuser?(conn.assigns.current_scope),
      snapshot: snap,
      media: Barn.media_urls(snap)
    })
  end

  def sync(conn, %{"ops" => ops}) when is_list(ops) do
    with :ok <- may_edit(conn) do
      user = conn.assigns.current_scope.user

      results =
        for op <- Enum.take(ops, 200) do
          case Barn.apply(op, user) do
            {:ok, _} -> %{client_id: op["client_id"], ok: true}
            {:error, msg} -> %{client_id: op["client_id"], ok: false, error: to_string(msg)}
          end
        end

      json(conn, %{ok: true, results: results})
    end
  end

  def sync(conn, _), do: conn |> put_status(400) |> json(%{ok: false, error: "Nothing to sync."})

  def photo(conn, %{"file" => %Plug.Upload{path: path}} = params) do
    with :ok <- may_edit(conn) do
      case Barn.save_photo(params, path, conn.assigns.current_scope.user) do
        {:ok, _} -> json(conn, %{ok: true})
        {:error, msg} -> conn |> put_status(422) |> json(%{ok: false, error: to_string(msg)})
      end
    end
  end

  def photo(conn, _), do: conn |> put_status(400) |> json(%{ok: false, error: "No photo."})

  defp may_edit(conn) do
    cond do
      not same_origin?(conn) ->
        conn |> put_status(403) |> json(%{ok: false, error: "Not from the app."}) |> halt()

      not Scope.superuser?(conn.assigns.current_scope) ->
        conn
        |> put_status(403)
        |> json(%{ok: false, error: "This account can't make changes."})
        |> halt()

      true ->
        :ok
    end
  end

  defp same_origin?(conn) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> URI.parse(origin).host == conn.host
    end
  end
end
