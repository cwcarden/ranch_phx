defmodule RanchPhx.StorageTest do
  use RanchPhxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RanchPhx.{Animals, Backup, Storage}
  alias RanchPhx.Backup.R2

  @moduletag :tmp_dir
  setup %{tmp_dir: dir} do
    Req.Test.set_req_test_to_shared()
    Application.put_env(:ranch_phx, :uploads_dir, dir)

    Application.put_env(:ranch_phx, :backup,
      account_id: "acct",
      access_key_id: "key",
      secret_access_key: "secret",
      bucket: "ranch"
    )

    on_exit(fn ->
      Application.delete_env(:ranch_phx, :uploads_dir)
      Application.delete_env(:ranch_phx, :backup)
    end)

    {:ok, a} =
      Animals.create_animal(%{name: "Gimels Soldier Cat", barn_name: "Asher", kind: "horse"})

    # One photo on disk, one the app points at that's gone (but in the backup), and
    # one gone that never made it into a backup.
    here = Storage.store(write_tmp(dir, "x"), "animals/#{a.id}/photos")
    {:ok, _} = Animals.create_photo(%{animal_id: a.id, url: here})

    {:ok, _} =
      Animals.create_photo(%{animal_id: a.id, url: "/uploads/animals/#{a.id}/photos/lost.jpg"})

    {:ok, _} =
      Animals.create_photo(%{animal_id: a.id, url: "/uploads/animals/#{a.id}/photos/never.jpg"})

    Req.Test.stub(R2, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/ranch"} ->
          Plug.Conn.send_resp(conn, 200, """
          <ListBucketResult><Contents><Key>uploads/animals/#{a.id}/photos/lost.jpg</Key><Size>4</Size></Contents>
          <IsTruncated>false</IsTruncated></ListBucketResult>
          """)

        {"GET", "/ranch/uploads/animals/" <> _} ->
          Plug.Conn.send_resp(conn, 200, "back")

        {"PUT", _} ->
          flunk("restoring must never write to the backup")

        {"DELETE", _} ->
          flunk("restoring must never delete anything")
      end
    end)

    %{animal: a, here: here, dir: dir}
  end

  defp write_tmp(dir, body) do
    p = Path.join(dir, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(p, body)
    p
  end

  test "new uploads go in the uploads folder and are served from it", %{
    conn: conn,
    here: here,
    dir: dir
  } do
    assert File.exists?(Path.join(dir, String.replace_prefix(here, "/uploads/", "")))
    assert conn |> get(here) |> response(200) == "x"
  end

  test "finds what's missing and puts back what the backup has, without touching what's there",
       %{animal: a, here: here, dir: dir} do
    assert Storage.missing() == [
             "/uploads/animals/#{a.id}/photos/lost.jpg",
             "/uploads/animals/#{a.id}/photos/never.jpg"
           ]

    assert {:ok, %{restored: 1, not_in_backup: 1}} = Backup.restore_missing()
    assert File.read!(Path.join(dir, "animals/#{a.id}/photos/lost.jpg")) == "back"
    assert File.read!(Storage.path(here)) == "x"
    assert Storage.missing() == ["/uploads/animals/#{a.id}/photos/never.jpg"]
  end

  test "files saved inside the release are copied out, never moved", %{dir: dir} do
    rel = Storage.release_dir()
    File.mkdir_p!(Path.join(rel, "storage-test"))
    src = Path.join(rel, "storage-test/old.jpg")
    File.write!(src, "old")
    on_exit(fn -> File.rm_rf(Path.join(rel, "storage-test")) end)

    assert Storage.adopt_release_files() >= 1
    assert File.read!(Path.join(dir, "storage-test/old.jpg")) == "old"
    assert File.exists?(src)
  end

  describe "Backup page" do
    setup :register_and_log_in_user

    test "checks and puts files back", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/backups")
      view |> element("#check-files") |> render_click()
      html = render_async(view)
      assert html =~ "2 file(s) missing on the server"
      assert html =~ "1 can be put back from the backup."

      view |> element("#restore-files") |> render_click()
      html = render_async(view)
      assert html =~ "Put back 1 file(s). 1 weren"
    end
  end
end
