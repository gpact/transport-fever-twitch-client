defmodule TF2Client.RequestsTest do
  use ExUnit.Case, async: false

  alias TF2Client.RateLimiter
  alias TF2Client.Requests
  alias TF2Client.RequestTracker

  @game_files_env "TF_INTEGRATION_GAME_FILES"

  setup do
    previous_disable_rate_limits = Application.get_env(:tf2_client, :disable_rate_limits)
    previous_request_queue_delays = Application.get_env(:tf2_client, :request_queue_delays_ms)
    previous_game_files_dir = System.get_env(@game_files_env)

    RateLimiter.reset()
    Application.put_env(:tf2_client, :request_queue_delays_ms, %{})

    on_exit(fn ->
      restore_app_env(:disable_rate_limits, previous_disable_rate_limits)
      restore_app_env(:request_queue_delays_ms, previous_request_queue_delays)
      restore_game_files_env(previous_game_files_dir)
    end)

    :ok
  end

  test "sends normalized Twitch color on vehicle purchases" do
    dir = prepare_game_files()
    ensure_request_tracker_started()

    tags = %{"color" => "#3BC43B"}

    assert {:reply, "@alice got it! I'll try to add a road vehicle for stone."} =
             Requests.handle_chat_command({:vehicle, "road", "stone"}, "alice", "somechannel", tags)

    lua = read_submitted_lua(dir)

    assert String.contains?(lua, ~s(request_type = "VEHICLE"))
    assert String.contains?(lua, "color = {")
    assert String.contains?(lua, "red = #{59 / 255}")
    assert String.contains?(lua, "green = #{196 / 255}")
    assert String.contains?(lua, "blue = #{59 / 255}")
  end

  test "sends normalized Twitch color on line purchases" do
    dir = prepare_game_files()
    ensure_request_tracker_started()

    tags = %{"color" => "#0000ff"}

    assert {:reply, "@alice got it! I'll try to set up a road line for stone."} =
             Requests.handle_chat_command({:line, "road", "stone"}, "alice", "somechannel", tags)

    lua = read_submitted_lua(dir)

    assert String.contains?(lua, ~s(request_type = "LINE"))
    assert String.contains?(lua, "color = {")
    assert String.contains?(lua, "red = 0.0")
    assert String.contains?(lua, "green = 0.0")
    assert String.contains?(lua, "blue = 1.0")
  end

  test "ignores invalid Twitch color on purchases" do
    dir = prepare_game_files()
    ensure_request_tracker_started()

    tags = %{"color" => "not-a-color"}

    assert {:reply, "@alice got it! I'll try to add a road vehicle for stone."} =
             Requests.handle_chat_command({:vehicle, "road", "stone"}, "alice", "somechannel", tags)

    lua = read_submitted_lua(dir)

    assert String.contains?(lua, ~s(request_type = "VEHICLE"))
    refute String.contains?(lua, "color =")
  end

  test "replies when a user hits a vehicle cooldown" do
    key = {:user, "alice", :purchase_vehicle}

    rule = %{
      cooldown_seconds: 5 * 60,
      window_seconds: 60 * 60,
      max_in_window: 3
    }

    assert :allow = RateLimiter.check(key, rule)

    assert {:reply, "@alice !vehicle is on cooldown for you for the next 5 minutes."} =
             Requests.handle_chat_command({:vehicle, "RAIL", "PASSENGERS"}, "alice", "somechannel")
  end

  test "replies when a user hits a stats cooldown" do
    key = {:user, "alice", :vehicles_owned}
    rule = %{cooldown_seconds: 60}

    assert :allow = RateLimiter.check(key, rule)

    assert {:reply, "@alice !vehicles is on cooldown for you for the next 1 minute."} =
             Requests.handle_chat_command({:vehicles_owned}, "alice", "somechannel")
  end

  test "replies when rank is on global cooldown" do
    key = {:global, :profit_rankings}
    rule = %{cooldown_seconds: 60}

    assert :allow = RateLimiter.check(key, rule)

    assert {:reply, "@bob !rank is on cooldown for everyone for the next 1 minute."} =
             Requests.handle_chat_command({:profit_rankings}, "bob", "somechannel")
  end

  test "returns game offline message when game state is missing" do
    empty_dir = temp_dir()
    File.mkdir_p!(empty_dir)
    System.put_env("TF_INTEGRATION_GAME_FILES", empty_dir)

    on_exit(fn ->
      System.delete_env("TF_INTEGRATION_GAME_FILES")
      File.rm_rf(empty_dir)
    end)

    reply = Requests.handle_chat_command({:profit}, "charlie", "somechannel")
    assert {:reply, msg} = reply
    assert String.contains?(msg, "Start Transport Fever with the integration enabled")
    refute String.contains?(msg, "Transport Fever 2")
  end

  test "sends SET_TOWN_CREATION_ENABLED request when enabling town creation" do
    dir = prepare_game_files()
    ensure_request_tracker_started()

    assert {:reply, "@admin got it! I'll try to enable town creation."} =
             Requests.handle_chat_command({:set_town_creation_enabled, true}, "admin", "channel")

    lua = read_submitted_lua(dir)

    assert String.contains?(lua, "schema_version = 1")
    assert String.contains?(lua, ~s(request_type = "SET_TOWN_CREATION_ENABLED"))
    assert String.contains?(lua, ~s(type = "SET_TOWN_CREATION_ENABLED"))
    assert String.contains?(lua, ~s(username = "admin"))
    assert String.contains?(lua, ~s(save_uuid = "save-123"))
    assert String.contains?(lua, "timestamp = ")
    assert String.contains?(lua, "enabled = true")
    refute String.contains?(lua, ~s(enabled = "true"))
    refute String.contains?(lua, ~s(enabled = "on"))
    refute String.contains?(lua, "townCreationEnabled")
    refute String.contains?(lua, "town_creation_enabled")
  end

  test "sends SET_TOWN_CREATION_ENABLED request when disabling town creation" do
    dir = prepare_game_files()
    ensure_request_tracker_started()

    assert {:reply, "@admin got it! I'll try to disable town creation."} =
             Requests.handle_chat_command({:set_town_creation_enabled, false}, "admin", "channel")

    lua = read_submitted_lua(dir)

    assert String.contains?(lua, "schema_version = 1")
    assert String.contains?(lua, ~s(request_type = "SET_TOWN_CREATION_ENABLED"))
    assert String.contains?(lua, ~s(type = "SET_TOWN_CREATION_ENABLED"))
    assert String.contains?(lua, ~s(username = "admin"))
    assert String.contains?(lua, ~s(save_uuid = "save-123"))
    assert String.contains?(lua, "timestamp = ")
    assert String.contains?(lua, "enabled = false")
    refute String.contains?(lua, ~s(enabled = "false"))
    refute String.contains?(lua, ~s(enabled = "off"))
    refute String.contains?(lua, "townCreationEnabled")
    refute String.contains?(lua, "town_creation_enabled")
  end

  defp prepare_game_files do
    dir = temp_dir()
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "gameState.json"), ~s({"save_uuid":"save-123"}))
    System.put_env(@game_files_env, dir)

    on_exit(fn -> File.rm_rf(dir) end)

    dir
  end

  defp ensure_request_tracker_started do
    case Process.whereis(RequestTracker) do
      nil -> start_supervised!(RequestTracker)
      _pid -> :ok
    end
  end

  defp read_submitted_lua(dir) do
    requests = File.read!(Path.join(dir, "requests.txt"))
    [order_id] = String.split(requests, "\n", trim: true)
    File.read!(Path.join(dir, "#{order_id}.lua"))
  end

  defp temp_dir do
    random_bytes = :crypto.strong_rand_bytes(6)
    suffix = Base.encode16(random_bytes, case: :lower)
    Path.join(System.tmp_dir!(), "tf2-client-requests-test-#{suffix}")
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:tf2_client, key)
  defp restore_app_env(key, value), do: Application.put_env(:tf2_client, key, value)

  defp restore_game_files_env(nil), do: System.delete_env(@game_files_env)
  defp restore_game_files_env(value), do: System.put_env(@game_files_env, value)
end
