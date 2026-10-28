defmodule RanchPhx.Backup.R2 do
  @moduledoc """
  The few Cloudflare R2 calls the backup needs (R2 speaks the S3 API): list, put, delete.
  Requests are signed with AWS SigV4 by Req.
  """

  @doc "R2 settings from the server's environment, or nil when not set up."
  def config do
    c = Application.get_env(:ranch_phx, :backup, [])

    if Enum.all?([:account_id, :access_key_id, :secret_access_key, :bucket], &present?(c[&1])),
      do: c
  end

  defp present?(v), do: is_binary(v) and String.trim(v) != ""

  @doc "Every object in the bucket as `%{key => size}`."
  def list(c), do: list(c, nil, %{})

  defp list(c, token, acc) do
    query =
      [{"list-type", "2"}] ++ if(token, do: [{"continuation-token", token}], else: [])

    url = base(c) <> "?" <> URI.encode_query(query, :rfc3986)

    with {:ok, %{status: 200, body: xml}} <- Req.get(url, opts(c)) do
      acc =
        Regex.scan(~r{<Contents>(.*?)</Contents>}s, xml, capture: :all_but_first)
        |> Enum.reduce(acc, fn [entry], acc ->
          [_, key] = Regex.run(~r{<Key>(.*?)</Key>}s, entry)
          [_, size] = Regex.run(~r{<Size>(\d+)</Size>}, entry)
          Map.put(acc, unescape(key), String.to_integer(size))
        end)

      case Regex.run(~r{<NextContinuationToken>(.*?)</NextContinuationToken>}s, xml) do
        [_, next] -> list(c, unescape(next), acc)
        nil -> {:ok, acc}
      end
    else
      other -> error(other)
    end
  end

  def put(c, key, body, content_type \\ "application/octet-stream") do
    case Req.put(
           object_url(c, key),
           opts(c) ++ [body: body, headers: [{"content-type", content_type}]]
         ) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      other -> error(other)
    end
  end

  def delete(c, key) do
    case Req.delete(object_url(c, key), opts(c)) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      other -> error(other)
    end
  end

  defp base(c), do: "https://#{c[:account_id]}.r2.cloudflarestorage.com/#{c[:bucket]}"

  defp object_url(c, key),
    do:
      base(c) <>
        "/" <>
        (key
         |> String.split("/")
         |> Enum.map_join("/", &URI.encode(&1, fn ch -> URI.char_unreserved?(ch) end)))

  defp opts(c) do
    [
      aws_sigv4: [
        access_key_id: c[:access_key_id],
        secret_access_key: c[:secret_access_key],
        service: :s3,
        region: "auto"
      ],
      decode_body: false,
      retry: :transient,
      receive_timeout: 120_000
    ] ++ Application.get_env(:ranch_phx, :backup_req_options, [])
  end

  defp unescape(s) do
    s
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end

  defp error({:ok, %{status: status, body: body}}) do
    code = with [_, c] <- Regex.run(~r{<Code>(.*?)</Code>}, to_string(body)), do: c
    {:error, "R2 said #{status}#{if code, do: " (#{code})"}"}
  end

  defp error({:error, e}), do: {:error, "Couldn't reach R2: #{Exception.message(e)}"}
end
