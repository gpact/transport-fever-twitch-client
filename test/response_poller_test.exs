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
    ensure_response_poller_started()
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

    RequestTracker.track(order_id, %{
      save_uuid: "save-123",
      channel: "streamer",
      username: "admin",
      type: "SET_TOWN_CREATION_ENABLED"
    })

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

    RequestTracker.track(order_id, %{
      save_uuid: "save-123",
      channel: "streamer",
      username: "admin",
      type: "SET_TOWN_CREATION_ENABLED"
    })

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

    RequestTracker.track(order_id, %{
      save_uuid: "save-123",
      channel: "streamer",
      username: "admin",
      type: "SET_SOME_FEATURE_ENABLED"
    })

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

  for {label, completed, error} <- [
        {"success", true, nil},
        {"failure", true, "No town available"},
        {"pending", false, nil}
      ] do
    test "#{label} response updates only its originating save queue" do
      order_id = "response-order"
      GameBridge.submit_with_order_id(order_id, "TOWN", "viewer", "save-a", %{})
      GameBridge.submit_with_order_id("other", "TOWN", "viewer", "save-b", %{})
      File.write!(GameBridge.game_state_path(), Jason.encode!(%{save_uuid: "save-b"}))

      RequestTracker.track(order_id, %{
        channel: "streamer",
        username: "viewer",
        type: "TOWN",
        save_uuid: "save-a"
      })

      File.write!(
        GameBridge.response_json_path(order_id),
        Jason.encode!(%{
          completed: unquote(completed),
          error: unquote(error),
          response: %{}
        })
      )

      poller = Process.whereis(ResponsePoller)
      send(poller, :tick)
      :sys.get_state(poller)

      assert_receive {:chat_message, "streamer", _}
      assert File.read!(GameBridge.requests_path("save-b")) == "other\n"

      assert File.read!(GameBridge.requests_path("save-a")) ==
               unquote(if completed, do: "", else: "response-order\n")

      assert is_nil(RequestTracker.get(order_id)) == unquote(completed)
      assert File.exists?(GameBridge.order_lua_path(order_id)) == unquote(not completed)
    end
  end

  test "retains terminal response and tracking until queue cleanup succeeds" do
    order_id = "retry-cleanup"
    GameBridge.submit_with_order_id(order_id, "TOWN", "viewer", "save-a", %{})

    RequestTracker.track(order_id, %{
      channel: "streamer",
      username: "viewer",
      type: "TOWN",
      save_uuid: "save-a"
    })

    File.write!(GameBridge.response_json_path(order_id), Jason.encode!(%{completed: true, response: %{}}))
    temporary = GameBridge.requests_path("save-a") <> ".tmp"
    File.mkdir!(temporary)

    poller = Process.whereis(ResponsePoller)
    send(poller, :tick)
    :sys.get_state(poller)
    assert RequestTracker.get(order_id)
    assert File.exists?(GameBridge.response_json_path(order_id))
    assert File.exists?(GameBridge.order_lua_path(order_id))
    refute_received {:chat_message, _, _}

    File.rmdir!(temporary)
    send(poller, :tick)
    :sys.get_state(poller)
    assert_receive {:chat_message, "streamer", _}
    assert is_nil(RequestTracker.get(order_id))
    assert File.read!(GameBridge.requests_path("save-a")) == ""
  end

  test "recovers queues after client restart and retains pending requests until terminal" do
    GameBridge.submit_with_order_id("recovered", "TOWN", "viewer", "old-save", %{})
    GameBridge.submit_with_order_id("waiting", "TOWN", "viewer", "other-save", %{})

    File.write!(
      GameBridge.response_json_path("recovered"),
      Jason.encode!(%{
        completed: true,
        error: "No town available"
      })
    )

    File.write!(GameBridge.response_json_path("waiting"), Jason.encode!(%{completed: false}))

    assert {:ok, state} = ResponsePoller.init(%{})
    assert {:noreply, state} = ResponsePoller.handle_info(:tick, state)
    assert File.read!(GameBridge.requests_path("old-save")) == ""
    assert File.read!(GameBridge.requests_path("other-save")) == "waiting\n"
    refute File.exists?(GameBridge.response_json_path("recovered"))
    assert File.exists?(GameBridge.order_lua_path("waiting"))
    refute_received {:chat_message, _, _}

    File.write!(GameBridge.response_json_path("waiting"), Jason.encode!(%{completed: true}))
    assert {:noreply, %{recovered_requests: []}} = ResponsePoller.handle_info(:tick, state)
    assert File.read!(GameBridge.requests_path("other-save")) == ""
    refute File.exists?(GameBridge.order_lua_path("waiting"))
  end

  defp clear_request_tracker do
    clear_request_tracker(Process.whereis(RequestTracker))
  end

  defp clear_request_tracker(nil), do: :ok

  defp clear_request_tracker(_pid) do
    Enum.each(RequestTracker.pending_ids(), &RequestTracker.untrack/1)
  end

  defp ensure_request_tracker_started do
    ensure_started(Process.whereis(RequestTracker), RequestTracker)
  end

  defp ensure_response_poller_started do
    ensure_started(Process.whereis(ResponsePoller), ResponsePoller)
  end

  defp ensure_started(nil, module), do: start_supervised!(module)
  defp ensure_started(_pid, _module), do: :ok

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
