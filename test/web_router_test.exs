defmodule TF2Client.Web.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  alias Plug.Conn
  alias TF2Client.ChatbotState
  alias TF2Client.Commands
  alias TF2Client.Web.Router

  @opts Router.init([])
  @test_channel "router_streamer"

  setup do
    ChatbotState.reset()
    :ok
  end

  test "GET / serves the Streamer Control Panel HTML" do
    conn =
      :get
      |> conn("/")
      |> Router.call(@opts)

    assert conn.status == 200
    assert Conn.get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert String.contains?(conn.resp_body, "Transport Fever")
    refute String.contains?(conn.resp_body, "Transport Fever 2")
    assert String.contains?(conn.resp_body, "Streamer Control Panel")
    assert String.contains?(conn.resp_body, "Quick Controls")
    assert String.contains?(conn.resp_body, "!tfon")
    assert String.contains?(conn.resp_body, "!tfoff")
    refute String.contains?(conn.resp_body, "!tf2on")
    refute String.contains?(conn.resp_body, "!tf2off")
  end

  test "GET /api/status returns JSON status" do
    conn =
      :get
      |> conn("/api/status?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn.status == 200
    assert Conn.get_resp_header(conn, "content-type") == ["application/json"]

    assert {:ok, body} = Jason.decode(conn.resp_body)
    assert Map.has_key?(body, "twitch")
    assert Map.has_key?(body, "bot")
    assert Map.has_key?(body, "purchases")
    assert Map.has_key?(body, "game")
    assert body["channel"] == @test_channel
  end

  test "GET /api/status exposes game file diagnostics" do
    previous_dir = System.get_env("TF_INTEGRATION_GAME_FILES")
    dir = Path.join(System.tmp_dir!(), "missing-game-#{System.unique_integer([:positive])}")
    System.put_env("TF_INTEGRATION_GAME_FILES", dir)

    on_exit(fn ->
      case previous_dir do
        nil -> System.delete_env("TF_INTEGRATION_GAME_FILES")
        value -> System.put_env("TF_INTEGRATION_GAME_FILES", value)
      end
    end)

    response =
      :get
      |> conn("/api/status")
      |> Router.call(@opts)

    assert response.status == 200
    path = Path.join(dir, "gameState.json")

    assert %{
             "game" => %{
               "status" => "waiting_for_game",
               "game_state_path" => ^path,
               "error_code" => "enoent",
               "error_message" => message
             }
           } = Jason.decode!(response.resp_body)

    assert message =~ "not found"
  end

  test "POST /api/bot/toggle toggles bot state" do
    assert ChatbotState.enabled?(@test_channel) == false

    conn1 =
      :post
      |> conn("/api/bot/toggle?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn1.status == 200
    assert {:ok, %{"bot" => %{"enabled" => true, "status" => "active"}}} = Jason.decode(conn1.resp_body)
    assert ChatbotState.enabled?(@test_channel) == true

    conn2 =
      :post
      |> conn("/api/bot/toggle?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn2.status == 200
    assert {:ok, %{"bot" => %{"enabled" => false, "status" => "standby"}}} = Jason.decode(conn2.resp_body)
    assert ChatbotState.enabled?(@test_channel) == false
  end

  test "POST /api/bot/enable and /api/bot/disable explicitly set bot state" do
    conn_enable =
      :post
      |> conn("/api/bot/enable?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn_enable.status == 200
    assert {:ok, %{"bot" => %{"enabled" => true}}} = Jason.decode(conn_enable.resp_body)
    assert ChatbotState.enabled?(@test_channel) == true

    conn_disable =
      :post
      |> conn("/api/bot/disable?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn_disable.status == 200
    assert {:ok, %{"bot" => %{"enabled" => false}}} = Jason.decode(conn_disable.resp_body)
    assert ChatbotState.enabled?(@test_channel) == false
  end

  test "POST /api/purchases/toggle pauses and resumes purchases" do
    conn1 =
      :post
      |> conn("/api/purchases/toggle?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn1.status == 200
    assert {:ok, body1} = Jason.decode(conn1.resp_body)
    assert body1["purchases"]["paused"] == true
    assert body1["purchases"]["status"] == "paused"

    assert Enum.all?(Commands.pausable_commands(), fn cmd ->
             to_string(cmd) in body1["purchases"]["paused_commands"]
           end)

    conn2 =
      :post
      |> conn("/api/purchases/toggle?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn2.status == 200
    assert {:ok, body2} = Jason.decode(conn2.resp_body)
    assert body2["purchases"]["paused"] == false
    assert body2["purchases"]["status"] == "allowed"
  end

  test "POST /api/purchases/pause and /api/purchases/resume explicitly control redemptions" do
    conn_pause =
      :post
      |> conn("/api/purchases/pause?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn_pause.status == 200
    assert {:ok, %{"purchases" => %{"paused" => true}}} = Jason.decode(conn_pause.resp_body)

    conn_resume =
      :post
      |> conn("/api/purchases/resume?channel=#{@test_channel}")
      |> Router.call(@opts)

    assert conn_resume.status == 200
    assert {:ok, %{"purchases" => %{"paused" => false}}} = Jason.decode(conn_resume.resp_body)
  end

  test "GET /api/oauth/url returns authorization URL JSON" do
    conn =
      :get
      |> conn("/api/oauth/url")
      |> Router.call(@opts)

    assert conn.status == 200
    assert {:ok, %{"url" => url}} = Jason.decode(conn.resp_body)
    assert String.contains?(url, "https://id.twitch.tv/oauth2/authorize")
    assert String.contains?(url, "client_id=")
  end

  test "POST /api/oauth/reauth returns status ok and URL" do
    conn =
      :post
      |> conn("/api/oauth/reauth")
      |> Router.call(@opts)

    assert conn.status == 200
    assert {:ok, %{"status" => "ok", "url" => url}} = Jason.decode(conn.resp_body)
    assert String.contains?(url, "https://id.twitch.tv/oauth2/authorize")
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

  test "GET /oauth/callback without params serves the oauth callback HTML" do
    conn =
      :get
      |> conn("/oauth/callback")
      |> Router.call(@opts)

    assert conn.status == 200
    assert Conn.get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert String.contains?(conn.resp_body, "parseOAuthHash")
  end

  test "GET /unknown_route returns 404" do
    conn =
      :get
      |> conn("/some/unknown/path")
      |> Router.call(@opts)

    assert conn.status == 404
    assert conn.resp_body == "Not found."
  end
end
