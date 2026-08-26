defmodule MyAppWeb.Plugs.VerifyResendSignature do
  @moduledoc """
  Verifies Resend webhook signatures (Svix scheme) without a `svix` dependency.

    * Headers: `svix-id`, `svix-timestamp`, `svix-signature`.
    * Signed content: `"\#{id}.\#{timestamp}.\#{raw body}"`, HMAC-SHA256.
    * Secret: `whsec_` prefix stripped, then base64-decoded to key bytes.
    * The signature header may carry several space-separated `v1,<sig>` values;
      any constant-time match passes.
    * Timestamps older or newer than `@tolerance` seconds are rejected.

  Requires the raw body captured by `MyAppWeb.Plugs.CacheRawBody`.
  """
  import Plug.Conn

  @tolerance 300

  def init(opts), do: opts

  def call(conn, _opts) do
    with [svix_id] <- get_req_header(conn, "svix-id"),
         [svix_ts] <- get_req_header(conn, "svix-timestamp"),
         [svix_sig] <- get_req_header(conn, "svix-signature"),
         :ok <- check_timestamp(svix_ts),
         body = raw_body(conn),
         :ok <- verify(svix_id, svix_ts, body, svix_sig) do
      conn
    else
      _ -> conn |> send_resp(401, "invalid signature") |> halt()
    end
  end

  defp raw_body(conn) do
    (conn.assigns[:raw_body] || []) |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp check_timestamp(ts) do
    now = System.system_time(:second)

    case Integer.parse(ts) do
      {t, ""} when abs(now - t) <= @tolerance -> :ok
      _ -> :error
    end
  end

  defp verify(id, ts, body, header) do
    secret =
      Application.fetch_env!(:my_app, :resend_webhook_secret)
      |> String.replace_prefix("whsec_", "")
      |> Base.decode64!()

    signed = "#{id}.#{ts}.#{body}"
    expected = :hmac |> :crypto.mac(:sha256, secret, signed) |> Base.encode64()

    header
    |> String.split(" ", trim: true)
    |> Enum.map(fn part -> part |> String.split(",", parts: 2) |> List.last() end)
    |> Enum.any?(fn sig -> Plug.Crypto.secure_compare(sig, expected) end)
    |> case do
      true -> :ok
      false -> :error
    end
  end
end
