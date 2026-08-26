defmodule MyAppWeb.Plugs.CacheRawBodyTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MyAppWeb.Plugs.CacheRawBody

  @parser_opts Plug.Parsers.init(
                 parsers: [:json],
                 pass: ["*/*"],
                 body_reader: {CacheRawBody, :read_body, []},
                 json_decoder: Jason
               )

  test "captures the raw body for webhook requests" do
    conn =
      :post
      |> conn("/webhooks/resend", ~s({"a":1}))
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(@parser_opts)

    assert conn.body_params == %{"a" => 1}
    assert IO.iodata_to_binary(Enum.reverse(conn.assigns.raw_body)) == ~s({"a":1})
  end

  test "does not retain bodies for other requests" do
    conn =
      :post
      |> conn("/users/log-in", ~s({"a":1}))
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(@parser_opts)

    assert conn.body_params == %{"a" => 1}
    refute Map.has_key?(conn.assigns, :raw_body)
  end
end
