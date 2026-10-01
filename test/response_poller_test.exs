defmodule TF2Client.ResponsePollerTest do
  use ExUnit.Case, async: false

  alias TF2Client.GameBridge
  alias TF2Client.RequestTracker
  alias TF2Client.ResponsePoller

  @game_files_env "TF_INTEGRATION_GAME_FILES"

  defmodule TestChatSender do
    @behaviour TF2Client.Chat

    @impl TF2Client.Chat
    def send(channel, message) do
      case Application.get_env(:tf2_client, :test_chat_recipient) do
        nil -> :ok
        test_pid -> Kernel.send(test_pid, {:chat_message, channel, message})
      end

      :ok
    end
  end

  setup do
    previous_game_files_dir = System.get_env(@game_files_env)
    previous_chat_sender = Application.get_env(:tf2_client, :chat_sender)
    Application.put_env(:tf2_client, :chat_sender, TestChatSender)
    Application.put_env(:tf2_client, :test_chat_recipient, self())

    dir = temp_dir()
    File.mkdir_p!(dir)
    System.put_env(@game_files_env, dir)

    ensure_request_tracker_started()
    clear_request_tracker()

    on_exit(fn ->
      clear_request_tracker()
      restore_env(@game_files_env, previous_game_files_dir)
      restore_app_env(:chat_sender, previous_chat_sender)
      Application.delete_env(:tf2_client, :test_chat_recipient)
      File.rm_rf(dir)
    end)

    {:ok, dir: dir}
  end

  test "polls and delivers SET_TOWN_CREATION_ENABLED response when confirmed enabled" do
    order_id = "test-order-1"
    RequestTracker.track(order_id, %{channel: "streamer", username: "admin", type: "SET_TOWN_CREATION_ENABLED"})
    File.write!(GameBridge.order_lua_path(order_id), "return {}")

    response_json =
      Jason.encode!(%{
        "username" => "admin",
        "type" => "SET_TOWN_CREATION_ENABLED",
        "completed" => true,
        "error" => nil,
        "response" => %{
          "setting" => "townCreationEnabled",
          "enabled" => true
        }
      })

    File.write!(GameBridge.response_json_path(order_id), response_json)

    poller = Process.whereis(ResponsePoller)
    send(poller, :tick)

    assert_receive {:chat_message, "streamer", "@admin town creation is now enabled"}, 1_000
    :sys.get_state(poller)

    assert RequestTracker.get(order_id) == nil
    refute File.exists?(GameBridge.response_json_path(order_id))
    refute File.exists?(GameBridge.order_lua_path(order_id))
  end

  test "polls and delivers SET_TOWN_CREATION_ENABLED response when confirmed disabled" do
    order_id = "test-order-2"
    RequestTracker.track(order_id, %{channel: "streamer", username: "admin", type: "SET_TOWN_CREATION_ENABLED"})
    File.write!(GameBridge.order_lua_path(order_id), "return {}")

    response_json =
      Jason.encode!(%{
        "username" => "admin",
        "type" => "SET_TOWN_CREATION_ENABLED",
        "completed" => true,
        "error" => nil,
        "response" => %{
          "setting" => "townCreationEnabled",
          "enabled" => false
        }
      })

    File.write!(GameBridge.response_json_path(order_id), response_json)

    poller = Process.whereis(ResponsePoller)
    send(poller, :tick)

    assert_receive {:chat_message, "streamer", "@admin town creation is now disabled"}, 1_000
    :sys.get_state(poller)

    assert RequestTracker.get(order_id) == nil
  end

  test "fills missing response metadata from tracked request" do
    order_id = "test-order-3"
    RequestTracker.track(order_id, %{channel: "streamer", username: "admin", type: "SET_SOME_FEATURE_ENABLED"})
    File.write!(GameBridge.order_lua_path(order_id), "return {}")

    response_json =
      Jason.encode!(%{
        "completed" => true,
        "error" => nil,
        "response" => %{
          "setting" => "someFeatureEnabled",
          "enabled" => false
        }
      })

    File.write!(GameBridge.response_json_path(order_id), response_json)

    poller = Process.whereis(ResponsePoller)
    send(poller, :tick)

    assert_receive {:chat_message, "streamer", "@admin some feature is now disabled"}, 1_000
    :sys.get_state(poller)

    assert RequestTracker.get(order_id) == nil
    refute File.exists?(GameBridge.response_json_path(order_id))
    refute File.exists?(GameBridge.order_lua_path(order_id))
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
    Path.join(System.tmp_dir!(), "tf2-client-poller-test-#{suffix}")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp restore_app_env(key, nil), do: Application.delete_env(:tf2_client, key)
  defp restore_app_env(key, value), do: Application.put_env(:tf2_client, key, value)
end
