defmodule TF2Client.BotTest do
  use ExUnit.Case, async: false

  alias TF2Client.Bot
  alias TF2Client.ChatbotState
  alias TF2Client.GameBridge
  alias TF2Client.RequestTracker

  @game_files_env "TF_INTEGRATION_GAME_FILES"

  setup do
    previous_game_files_dir = System.get_env(@game_files_env)
    ChatbotState.reset()
    ensure_request_tracker_started()
    clear_request_tracker()

    dir = temp_dir()
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "gameState.json"), ~s({"save_uuid":"save-123"}))
    System.put_env(@game_files_env, dir)

    on_exit(fn ->
      clear_request_tracker()

      if previous_game_files_dir do
        System.put_env(@game_files_env, previous_game_files_dir)
      else
        System.delete_env(@game_files_env)
      end

      File.rm_rf(dir)
    end)

    {:ok, dir: dir}
  end

  test "ignores !towncreation from regular viewers", %{dir: dir} do
    before_ids = RequestTracker.pending_ids()

    assert :ok = Bot.handle_message("!towncreation on", "random_viewer", "streamer", %{})

    after_ids = RequestTracker.pending_ids()
    assert after_ids == before_ids

    requests_file = Path.join(dir, "requests.txt")
    refute File.exists?(requests_file)
  end

  test "accepts !towncreation from channel owner / broadcaster" do
    assert :ok = Bot.handle_message("!towncreation on", "streamer", "streamer", %{})

    pending = RequestTracker.pending_ids()
    assert length(pending) == 1
    [order_id] = pending

    lua = File.read!(GameBridge.order_lua_path(order_id))
    assert String.contains?(lua, ~s(request_type = "SET_TOWN_CREATION_ENABLED"))
    assert String.contains?(lua, "enabled = true")
  end

  test "accepts !towncreation from moderators" do
    tags = %{"mod" => "1"}
    assert :ok = Bot.handle_message("!towncreation off", "some_mod", "streamer", tags)

    pending = RequestTracker.pending_ids()
    assert length(pending) == 1
    [order_id] = pending

    lua = File.read!(GameBridge.order_lua_path(order_id))
    assert String.contains?(lua, ~s(request_type = "SET_TOWN_CREATION_ENABLED"))
    assert String.contains?(lua, "enabled = false")
  end

  test "accepts !towncreation from broadcaster badges" do
    tags = %{"badges" => "broadcaster/1,subscriber/0"}
    assert :ok = Bot.handle_message("!towncreation on", "owner", "streamer", tags)

    pending = RequestTracker.pending_ids()
    assert length(pending) == 1
  end

  defp clear_request_tracker do
    Enum.each(RequestTracker.pending_ids(), &RequestTracker.untrack/1)
  end

  defp ensure_request_tracker_started do
    case Process.whereis(RequestTracker) do
      nil -> start_supervised!(RequestTracker)
      _pid -> :ok
    end
  end

  defp temp_dir do
    random_bytes = :crypto.strong_rand_bytes(6)
    suffix = Base.encode16(random_bytes, case: :lower)
    Path.join(System.tmp_dir!(), "tf2-client-bot-test-#{suffix}")
  end
end
