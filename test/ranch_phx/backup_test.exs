defmodule RanchPhx.BackupTest do
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.Backup
  alias RanchPhx.Backup.R2

  @moduletag :tmp_dir
  setup %{tmp_dir: dir} do
    Req.Test.set_req_test_to_shared()
    File.mkdir_p!(Path.join(dir, "animals/1/documents"))
    File.mkdir_p!(Path.join(dir, "animals/1/photos"))
    File.write!(Path.join(dir, "animals/1/documents/coggins.pdf"), "pdf bytes")
    File.write!(Path.join(dir, "animals/1/photos/old.jpg"), "already there")
    File.write!(Path.join(dir, "animals/1/photos/new.jpg"), "new photo")

    Application.put_env(:ranch_phx, :backup_uploads_dir, dir)

    Application.put_env(:ranch_phx, :backup,
      account_id: "acct",
      access_key_id: "key",
      secret_access_key: "secret",
      bucket: "ranch"
    )

    on_exit(fn ->
      Application.delete_env(:ranch_phx, :backup_uploads_dir)
      Application.delete_env(:ranch_phx, :backup)
    end)

    {:ok, calls} = Agent.start_link(fn -> [] end)
    %{calls: calls, dir: dir}
  end

  # R2 already has old.jpg (same size) and 20 nightly database copies.
  defp stub_r2(calls, opts \\ []) do
    old_dumps =
      for i <- 1..20,
          do: {"db/ranch-#{Date.add(~D[2026-01-01], i * 7)}.dump", 100}

    objects = [{"uploads/animals/1/photos/old.jpg", 13} | old_dumps]

    Req.Test.stub(R2, fn conn ->
      Agent.update(calls, &(&1 ++ [{conn.method, conn.request_path}]))
      assert ["AWS4-HMAC-SHA256" <> _] = Plug.Conn.get_req_header(conn, "authorization")

      case conn.method do
        "GET" ->
          contents =
            Enum.map_join(objects, fn {k, s} ->
              "<Contents><Key>#{k}</Key><Size>#{s}</Size></Contents>"
            end)

          Plug.Conn.send_resp(
            conn,
            200,
            "<ListBucketResult>#{contents}<IsTruncated>false</IsTruncated></ListBucketResult>"
          )

        "PUT" ->
          if opts[:fail_put],
            do: Plug.Conn.send_resp(conn, 403, "<Error><Code>AccessDenied</Code></Error>"),
            else: Plug.Conn.send_resp(conn, 200, "")

        "DELETE" ->
          Plug.Conn.send_resp(conn, 204, "")
      end
    end)
  end

  test "sends the database, then documents, then new photos; skips what R2 has", %{calls: calls} do
    stub_r2(calls)
    assert {:ok, run} = Backup.run("manual")
    assert {run.status, run.error} == {"ok", nil}
    assert run.db_bytes > 0
    assert run.files_uploaded == 3

    puts = for {"PUT", path} <- Agent.get(calls, & &1), do: path

    assert [
             db,
             "/ranch/uploads/animals/1/documents/coggins.pdf",
             "/ranch/uploads/animals/1/photos/new.jpg"
           ] = puts

    assert db =~ ~r"^/ranch/db/ranch-\d{4}-\d{2}-\d{2}\.dump$"

    # Older nightly copies beyond 14 (and not the monthly keepers) are removed.
    deletes = for {"DELETE", path} <- Agent.get(calls, & &1), do: path
    assert deletes != []
    assert Enum.all?(deletes, &String.starts_with?(&1, "/ranch/db/"))
  end

  test "records the error when R2 refuses", %{calls: calls} do
    stub_r2(calls, fail_put: true)
    assert {:ok, run} = Backup.run("manual")
    assert run.status == "error"
    assert run.error =~ "AccessDenied"
    assert [%{status: "error"}] = Backup.last_runs()
  end

  test "keeps 14 nightly copies and one a month for a year" do
    keys = for i <- 0..399, do: "db/ranch-#{Date.add(~D[2025-01-01], i)}.dump"
    drop = Backup.dumps_to_drop(["uploads/x.jpg" | keys])
    kept = keys -- drop
    # The last 14 nights cover Jan 22–Feb 4, which already hold Feb's and Jan's newest.
    assert length(kept) == 14 + 10
    assert "db/ranch-2026-02-04.dump" in kept
    refute "uploads/x.jpg" in drop
  end

  describe "page" do
    setup :register_and_log_in_user

    test "shows status and backs up on tap", %{conn: conn, calls: calls} do
      stub_r2(calls)
      {:ok, view, _} = live(conn, ~p"/admin/backups")
      assert has_element?(view, "#backup-state", "No backup yet")
      view |> element("#backup-now") |> render_click()
      # Makes a real copy of the test database, which can take a moment.
      render_async(view, 10_000)
      assert has_element?(view, "#backup-state", "Backed up")
      assert has_element?(view, "#backup-runs", "3 new file(s)")
    end

    test "explains setup when R2 isn't configured", %{conn: conn} do
      Application.delete_env(:ranch_phx, :backup)
      {:ok, view, _} = live(conn, ~p"/admin/backups")
      assert has_element?(view, "#backup-state", "Not backed up")
      refute has_element?(view, "#backup-now")
      assert has_element?(view, "#backup-setup[open]")
    end
  end
end
