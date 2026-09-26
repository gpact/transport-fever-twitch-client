defmodule TF2Client.Web.StatusTest do
  use ExUnit.Case, async: false

  alias TF2Client.ChatbotState
  alias TF2Client.Commands
  alias TF2Client.Web.Status

  @test_channel "test_streamer"
  @test_dir Path.join(__DIR__, "../tmp/test_web_status")
  @game_state_file Path.join(@test_dir, "gameState.json")

  setup do
    File.mkdir_p!(@test_dir)
    System.put_env("TF_INTEGRATION_GAME_FILES", @test_dir)

    ChatbotState.reset()

    on_exit(fn ->
      System.delete_env("TF_INTEGRATION_GAME_FILES")
      File.rm_rf(@test_dir)
    end)

    :ok
  end

  describe "twitch_status/0" do
    test "returns disconnected when TMI channel server is not started" do
      status = Status.twitch_status()
      assert status.connected == false
      assert status.status in ["disconnected", "connecting"]
    end
  end

  describe "bot_status/1 and bot mutations" do
    test "reports standby when disabled and active when enabled" do
      ChatbotState.disable(@test_channel)
      assert %{enabled: false, status: "standby"} = Status.bot_status(@test_channel)

      assert {:ok, true} = Status.enable_bot(@test_channel)
      assert %{enabled: true, status: "active"} = Status.bot_status(@test_channel)

      assert {:ok, false} = Status.disable_bot(@test_channel)
      assert %{enabled: false, status: "standby"} = Status.bot_status(@test_channel)

      assert {:ok, true} = Status.toggle_bot(@test_channel)
      assert %{enabled: true, status: "active"} = Status.bot_status(@test_channel)

      assert {:ok, false} = Status.toggle_bot(@test_channel)
      assert %{enabled: false, status: "standby"} = Status.bot_status(@test_channel)
    end

    test "handles nil channel gracefully" do
      assert %{enabled: false, status: "standby"} = Status.bot_status(nil)
    end
  end

  describe "purchases_status/1 and purchase mutations" do
    test "reports allowed by default, and paused when all redemptions are paused" do
      assert %{paused: false, status: "allowed"} = Status.purchases_status(@test_channel)

      assert {:ok, true} = Status.pause_purchases(@test_channel)
      status = Status.purchases_status(@test_channel)
      assert status.paused == true
      assert status.status == "paused"

      assert Enum.all?(Commands.pausable_commands(), fn cmd ->
               to_string(cmd) in status.paused_commands
             end)

      assert {:ok, false} = Status.resume_purchases(@test_channel)
      assert %{paused: false, status: "allowed"} = Status.purchases_status(@test_channel)

      assert {:ok, true} = Status.toggle_purchases(@test_channel)
      assert %{paused: true, status: "paused"} = Status.purchases_status(@test_channel)

      assert {:ok, false} = Status.toggle_purchases(@test_channel)
      assert %{paused: false, status: "allowed"} = Status.purchases_status(@test_channel)
    end

    test "handles nil channel gracefully" do
      assert %{paused: false, status: "allowed"} = Status.purchases_status(nil)
    end
  end

  describe "game_status/0" do
    test "returns waiting_for_game when gameState.json is missing" do
      status = Status.game_status()
      assert status.connected == false
      assert status.status == "waiting_for_game"
      assert status.save_uuid == nil
      assert status.last_updated_seconds_ago == nil
    end

    test "returns connected when gameState.json is recently updated" do
      File.write!(@game_state_file, Jason.encode!(%{"save_uuid" => "save-uuid-123"}))

      status = Status.game_status()
      assert status.connected == true
      assert status.status == "connected"
      assert status.save_uuid == "save-uuid-123"
      assert is_integer(status.last_updated_seconds_ago)
      assert status.last_updated_seconds_ago <= 5
    end

    test "returns stale when gameState.json has not been modified recently" do
      File.write!(@game_state_file, Jason.encode!(%{"save_uuid" => "save-uuid-456"}))

      # Simulate mtime 60 seconds ago
      past_time = System.os_time(:second) - 60
      erl_time = :calendar.system_time_to_universal_time(past_time, :second)
      File.touch!(@game_state_file, erl_time)

      status = Status.game_status()
      assert status.connected == true
      assert status.status == "stale"
      assert status.save_uuid == "save-uuid-456"
      assert status.last_updated_seconds_ago >= 50
    end
  end

  describe "current_status/1" do
    test "returns comprehensive system status map" do
      status = Status.current_status(@test_channel)
      assert is_map(status)
      assert Map.has_key?(status, :twitch)
      assert Map.has_key?(status, :bot)
      assert Map.has_key?(status, :purchases)
      assert Map.has_key?(status, :game)
      assert status.channel == @test_channel
    end
  end
end
