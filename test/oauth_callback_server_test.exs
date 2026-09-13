defmodule TF2Client.Twitch.OAuthCallbackServerTest do
  use ExUnit.Case, async: false
  import Plug.Test
  alias Plug.Conn
  alias TF2Client.Twitch.OAuthCallbackServer
  alias TF2Client.Twitch.OAuthCallbackServer.Router

  @opts Router.init([])

  test "GET /oauth/callback without parameters serves the interactive HTML page" do
    conn =
      :get
      |> conn("/oauth/callback")
      |> Router.call(@opts)

    assert conn.status == 200
    assert Conn.get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert String.contains?(conn.resp_body, "Transport Fever 2 Twitch Bot")
    assert String.contains?(conn.resp_body, "parseOAuthHash")
  end

  test "OPTIONS /oauth/token handles CORS preflight" do
    conn =
      :options
      |> conn("/oauth/token")
      |> Router.call(@opts)

    assert conn.status == 204
    assert Conn.get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert Conn.get_resp_header(conn, "access-control-allow-methods") == ["POST, OPTIONS"]
  end

  test "POST /oauth/token and GET /oauth/callback?access_token deliver token to server caller" do
    caller = self()
    {:ok, _pid} = OAuthCallbackServer.start_link(caller: caller)

    try do
      assert :ok =
               OAuthCallbackServer.deliver_token(%{
                 access_token: "unit_test_implicit_token",
                 expires_in: 3600
               })

      assert_receive {:twitch_oauth_token, %{access_token: "unit_test_implicit_token", expires_in: 3600}}
    after
      OAuthCallbackServer.stop()
    end
  end

  test "delivering code delivers code to caller" do
    caller = self()
    {:ok, _pid} = OAuthCallbackServer.start_link(caller: caller)

    try do
      assert :ok = OAuthCallbackServer.deliver_code("unit_test_code")
      assert_receive {:twitch_oauth_code, "unit_test_code"}
    after
      OAuthCallbackServer.stop()
    end
  end
end
