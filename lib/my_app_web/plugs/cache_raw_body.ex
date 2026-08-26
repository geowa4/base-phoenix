defmodule MyAppWeb.Plugs.CacheRawBody do
  @moduledoc """
  `Plug.Parsers` body reader that keeps the raw request body in
  `conn.assigns.raw_body` (as a reversed list of chunks) for HMAC
  verification of inbound webhooks. Only webhook requests are captured.
  """

  @webhook_prefix "webhooks"

  def read_body(%Plug.Conn{path_info: [@webhook_prefix | _]} = conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], fn chunks -> [body | chunks || []] end)
    {:ok, body, conn}
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)
end
