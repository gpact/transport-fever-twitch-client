defmodule TF2Client.GameBridgeTest do
  use ExUnit.Case, async: true

  alias TF2Client.GameBridge

  setup do
    dir = Path.join(System.tmp_dir!(), "tf2-client-test-#{Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)}")
    File.mkdir_p!(dir)

    previous = System.get_env("TF2_INTEGRATION_GAME_FILES")
    System.put_env("TF2_INTEGRATION_GAME_FILES", dir)

    on_exit(fn ->
      if is_binary(previous), do: System.put_env("TF2_INTEGRATION_GAME_FILES", previous), else: System.delete_env("TF2_INTEGRATION_GAME_FILES")
      File.rm_rf(dir)
    end)

    {:ok, dir: dir}
  end

  test "writes lua order file and appends to requests.txt", %{dir: dir} do
    File.write!(Path.join(dir, "gameState.json"), ~s({"save_uuid":"save-123"}))

    assert {:ok, order_id} = GameBridge.submit("COMPANY", "someuser", %{company_name: "Some Co"})
    assert byte_size(order_id) == 32
    assert File.exists?(GameBridge.order_lua_path(order_id))
    assert File.exists?(GameBridge.requests_path())

    requests = File.read!(GameBridge.requests_path())
    assert String.contains?(requests, order_id)

    lua = File.read!(GameBridge.order_lua_path(order_id))
    assert String.contains?(lua, ~s(schema_version))
    assert String.contains?(lua, ~s(request_type = "COMPANY"))
    assert String.contains?(lua, ~s(username = "someuser"))
    assert String.contains?(lua, ~s(save_uuid = "save-123"))
    assert String.contains?(lua, ~s(company_name = "Some Co"))
  end
end

