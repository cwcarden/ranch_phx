defmodule RanchPhx.Push.WebPush do
  @moduledoc """
  Sends a Web Push message: the payload encrypted for the device (RFC 8291,
  aes128gcm) and signed with the app's VAPID key (RFC 8292). Pure Erlang :crypto.
  """

  @doc "Encrypts `payload` for a device's `p256dh` public key and `auth` secret (both raw bytes)."
  def encrypt(payload, ua_public, auth_secret, opts \\ []) do
    {as_public, as_private} = opts[:server_keys] || :crypto.generate_key(:ecdh, :prime256v1)
    salt = opts[:salt] || :crypto.strong_rand_bytes(16)

    shared = :crypto.compute_key(:ecdh, ua_public, as_private, :prime256v1)
    prk_key = hmac(auth_secret, shared)

    ikm =
      hmac(prk_key, "WebPush: info" <> <<0>> <> ua_public <> as_public <> <<1>>)
      |> binary_part(0, 32)

    prk = hmac(salt, ikm)
    cek = hmac(prk, "Content-Encoding: aes128gcm" <> <<0, 1>>) |> binary_part(0, 16)
    nonce = hmac(prk, "Content-Encoding: nonce" <> <<0, 1>>) |> binary_part(0, 12)

    # One record: the payload, then the last-record delimiter.
    {cipher, tag} =
      :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, payload <> <<2>>, <<>>, true)

    salt <> <<4096::unsigned-big-32, byte_size(as_public)::8>> <> as_public <> cipher <> tag
  end

  @doc "The VAPID Authorization header value for `endpoint`."
  def vapid_header(endpoint, public_key, private_key, subject) do
    %URI{scheme: scheme, host: host} = URI.parse(endpoint)
    header = b64(Jason.encode!(%{typ: "JWT", alg: "ES256"}))

    claims =
      b64(
        Jason.encode!(%{
          aud: "#{scheme}://#{host}",
          exp: System.system_time(:second) + 12 * 3600,
          sub: subject
        })
      )

    input = header <> "." <> claims
    der = :crypto.sign(:ecdsa, :sha256, input, [private_key, :prime256v1])
    "vapid t=#{input}.#{b64(der_to_raw(der))}, k=#{b64(public_key)}"
  end

  # ECDSA signatures come back as DER; JWT wants the raw 32-byte r and s.
  defp der_to_raw(<<0x30, _len, 0x02, rl, r::binary-size(rl), 0x02, sl, s::binary-size(sl)>>),
    do: pad32(r) <> pad32(s)

  defp pad32(n) do
    n = n |> :binary.bin_to_list() |> Enum.drop_while(&(&1 == 0)) |> :binary.list_to_bin()
    :binary.copy(<<0>>, 32 - byte_size(n)) <> n
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  def b64(bin), do: Base.url_encode64(bin, padding: false)

  def unb64(str) do
    str =
      String.replace(str, ["+", "/"], fn
        "+" -> "-"
        "/" -> "_"
      end)

    Base.url_decode64!(String.trim_trailing(str, "="), padding: false)
  end
end
